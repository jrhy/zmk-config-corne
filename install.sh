#!/bin/bash
set -e

# ZMK Firmware Installer for Corne Keyboard
# Downloads tools, verifies checksums, and flashes firmware to both halves
# Tolerates expected errors from keyboard rebooting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/zmk-corne-install"
mkdir -p "$WORK_DIR"

# Tool URLs and checksums - pinned to specific commit for stability
UF2_COMMIT="2c8dbaf81bfd5455154ba3b019751766effbd6e7"  # Nov 19, 2025
UF2CONV_URL="https://raw.githubusercontent.com/microsoft/uf2/${UF2_COMMIT}/utils/uf2conv.py"
UF2FAMILIES_URL="https://raw.githubusercontent.com/microsoft/uf2/${UF2_COMMIT}/utils/uf2families.json"

# SHA256 checksums - verify with: shasum -a 256 filename
UF2CONV_SHA256="ad36ba2d61fb2ea371832262392088281eee474c609df4142adbee4ea3c20f26"
UF2FAMILIES_SHA256="c8a3f8e70eef3db3e46b324e2cc54cd7fdac1b8cf873d37506221ddd77249e32"

log() {
    echo "📱 $1"
}

error() {
    echo "❌ $1" >&2
    exit 1
}

verify_checksum() {
    local file=$1
    local expected=$2
    local name=$3
    local quiet=${4:-false}

    if ! command -v shasum &> /dev/null; then
        [ "$quiet" != "true" ] && log "⚠️  shasum not found, skipping checksum verification for $name"
        return 0
    fi

    [ ! -f "$file" ] && return 1

    local actual=$(shasum -a 256 "$file" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        [ "$quiet" != "true" ] && error "Checksum mismatch for $name!\nExpected: $expected\nActual: $actual"
        return 1
    fi
    [ "$quiet" != "true" ] && log "✅ Checksum verified for $name"
    return 0
}

download_tools() {
    # Check if uf2conv.py already exists with correct checksum
    if verify_checksum "$WORK_DIR/uf2conv.py" "$UF2CONV_SHA256" "uf2conv.py" true; then
        log "✅ uf2conv.py already cached"
    else
        log "Downloading uf2conv.py..."
        curl -sL -o "$WORK_DIR/uf2conv.py" "$UF2CONV_URL" || error "Failed to download uf2conv.py"
        chmod +x "$WORK_DIR/uf2conv.py"
        verify_checksum "$WORK_DIR/uf2conv.py" "$UF2CONV_SHA256" "uf2conv.py"
    fi

    # Check if uf2families.json already exists with correct checksum
    if verify_checksum "$WORK_DIR/uf2families.json" "$UF2FAMILIES_SHA256" "uf2families.json" true; then
        log "✅ uf2families.json already cached"
    else
        log "Downloading uf2families.json..."
        curl -sL -o "$WORK_DIR/uf2families.json" "$UF2FAMILIES_URL" || error "Failed to download uf2families.json"
        verify_checksum "$WORK_DIR/uf2families.json" "$UF2FAMILIES_SHA256" "uf2families.json"
    fi
}

download_firmware() {
    local repo="${1:-jrhy/zmk-config-corne}"
    local branch="${2:-main}"

    log "Checking for latest firmware from $repo ($branch)..."

    # Get latest successful run on the specified branch
    local run_id=$(gh run list -R "$repo" --branch "$branch" --status success --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)

    if [ -z "$run_id" ]; then
        error "No successful builds found for $repo on branch $branch. Check GitHub Actions."
    fi

    # Check if we already have this run cached
    local cached_run_id=""
    [ -f "$WORK_DIR/firmware/.run_id" ] && cached_run_id=$(cat "$WORK_DIR/firmware/.run_id")

    if [ "$run_id" = "$cached_run_id" ] && [ -f "$WORK_DIR/firmware/corne_left-nice_nano@2.0.0-zmk.uf2" ]; then
        log "✅ Firmware already cached (run $run_id)"
        return 0
    fi

    log "Downloading firmware (run $run_id)..."

    # Clean up any previous firmware downloads
    rm -rf "$WORK_DIR/firmware"

    gh run download "$run_id" -R "$repo" -D "$WORK_DIR/firmware" || error "Failed to download firmware"

    # gh downloads to nested firmware/firmware/ directory, flatten if needed
    if [ -d "$WORK_DIR/firmware/firmware" ]; then
        mv "$WORK_DIR/firmware/firmware"/* "$WORK_DIR/firmware/" 2>/dev/null || true
        rmdir "$WORK_DIR/firmware/firmware" 2>/dev/null || true
    fi

    # Cache the run_id
    echo "$run_id" > "$WORK_DIR/firmware/.run_id"
}

flash_half() {
    local fw_file=$1
    local side=$2
    local uf2conv=$3

    log "Flashing $side half..."
    log "   Put $side half in bootloader mode (double-tap reset button)"
    read -p "Press ENTER when ready... "

    # Run uf2conv.py, but tolerate I/O errors from keyboard rebooting
    if ! python3 "$uf2conv" -w -D "$fw_file" 2>&1 | grep -q "Input/output error"; then
        # If there's NO I/O error, check for actual failures
        if ! python3 "$uf2conv" -w -D "$fw_file" 2>&1; then
            error "Failed to flash $side half"
        fi
    else
        # I/O error is expected and usually means flash succeeded
        log "   (I/O error during reboot is normal on macOS)"
    fi

    log "✅ $side half flashed!"
    sleep 2
}

reset_half() {
    local reset_fw=$1
    local side=$2
    local uf2conv=$3

    log "Resetting $side half..."
    log "   Put $side half in bootloader mode (double-tap reset button)"
    read -p "Press ENTER when ready... "

    # Tolerate I/O errors during reset too
    if ! python3 "$uf2conv" -w -D "$reset_fw" 2>&1 | grep -q "Input/output error"; then
        if ! python3 "$uf2conv" -w -D "$reset_fw" 2>&1; then
            error "Failed to reset $side half"
        fi
    else
        log "   (I/O error during reboot is normal on macOS)"
    fi

    log "✅ $side half reset!"
    sleep 2
}

main() {
    log "ZMK Corne Firmware Installer"
    log "============================"
    echo ""

    # Check for required tools
    command -v gh &> /dev/null || error "gh (GitHub CLI) is required. Install from https://cli.github.com"
    command -v python3 &> /dev/null || error "python3 is required"

    # Parse arguments
    local repo="${1:-jrhy/zmk-config-corne}"
    local branch="${2:-main}"
    local skip_reset="${3:-false}"

    log "Repository: $repo"
    log "Branch: $branch"
    echo ""

    # Download tools
    download_tools
    echo ""

    # Download firmware
    download_firmware "$repo" "$branch"
    echo ""

    # Find firmware files
    local left_fw="$WORK_DIR/firmware/corne_left-nice_nano@2.0.0-zmk.uf2"
    local right_fw="$WORK_DIR/firmware/corne_right-nice_nano@2.0.0-zmk.uf2"
    local reset_fw="$WORK_DIR/firmware/settings_reset-nice_nano@2.0.0-zmk.uf2"

    # Verify firmware exists
    [ -f "$left_fw" ] || error "Left firmware not found: $left_fw"
    [ -f "$right_fw" ] || error "Right firmware not found: $right_fw"
    [ -f "$reset_fw" ] || error "Reset firmware not found: $reset_fw"

    log "Firmware files found ✅"
    echo ""

    # Reset halves if not skipped
    if [ "$skip_reset" != "true" ]; then
        log "Step 1: Resetting keyboard settings"
        reset_half "$reset_fw" "RIGHT" "$WORK_DIR/uf2conv.py"
        reset_half "$reset_fw" "LEFT" "$WORK_DIR/uf2conv.py"
        echo ""
    fi

    # Flash firmware
    log "Step 2: Flashing firmware"
    flash_half "$left_fw" "LEFT" "$WORK_DIR/uf2conv.py"
    flash_half "$right_fw" "RIGHT" "$WORK_DIR/uf2conv.py"

    echo ""
    log "✨ Installation complete!"
    log "Both halves should now be booting with your customized firmware."
    echo ""
}

main "$@"
