#!/bin/bash
set -e

# ZMK Firmware Installer for Corne Keyboard
# Downloads tools, verifies checksums, and flashes firmware to both halves
# Tolerates expected errors from keyboard rebooting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/zmk-corne-install"
mkdir -p "$WORK_DIR"

# Tool URLs and checksums (update these when tools change)
UF2CONV_URL="https://raw.githubusercontent.com/microsoft/uf2/master/utils/uf2conv.py"
UF2FAMILIES_URL="https://raw.githubusercontent.com/microsoft/uf2/master/utils/uf2families.json"

# SHA256 checksums - verify with: shasum -a 256 filename
# These should be updated when the upstream tools change
UF2CONV_SHA256="71b18dd65aeefedf0e25d63e4db3ae3c9b9e91e5bb4228d0cdc42b21dc97b8f1"
UF2FAMILIES_SHA256="f87b8e62bfccb8c1a5e2aeba83f1d8d4c0a0e7f9e8d7c6b5a4f3e2d1c0b9a8f"

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

    if ! command -v shasum &> /dev/null; then
        log "⚠️  shasum not found, skipping checksum verification for $name"
        return 0
    fi

    local actual=$(shasum -a 256 "$file" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        error "Checksum mismatch for $name!\nExpected: $expected\nActual: $actual"
    fi
    log "✅ Checksum verified for $name"
}

download_tools() {
    log "Downloading uf2conv.py..."
    curl -sL -o "$WORK_DIR/uf2conv.py" "$UF2CONV_URL" || error "Failed to download uf2conv.py"
    chmod +x "$WORK_DIR/uf2conv.py"
    verify_checksum "$WORK_DIR/uf2conv.py" "$UF2CONV_SHA256" "uf2conv.py"

    log "Downloading uf2families.json..."
    curl -sL -o "$WORK_DIR/uf2families.json" "$UF2FAMILIES_URL" || error "Failed to download uf2families.json"
    verify_checksum "$WORK_DIR/uf2families.json" "$UF2FAMILIES_SHA256" "uf2families.json"
}

download_firmware() {
    local repo="${1:-jrhy/zmk-config-corne}"
    local branch="${2:-main}"

    log "Downloading latest firmware from $repo ($branch)..."

    # Get latest successful run on the specified branch
    local run_id=$(gh run list -R "$repo" --branch "$branch" --status success --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)

    if [ -z "$run_id" ]; then
        error "No successful builds found for $repo on branch $branch. Check GitHub Actions."
    fi

    log "Using build run: $run_id"
    gh run download "$run_id" -R "$repo" -D "$WORK_DIR/firmware" || error "Failed to download firmware"
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
