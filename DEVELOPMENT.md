# ZMK Corne Development Notes

## Key Position Map

Use these position numbers when defining combos in `config/corne.keymap`.

```
╭───┬───┬───┬───┬───┬───╮   ╭───┬───┬───┬───┬───┬───╮
│ 0 │ 1 │ 2 │ 3 │ 4 │ 5 │   │ 6 │ 7 │ 8 │ 9 │10 │11 │
├───┼───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┼───┤
│12 │13 │14 │15 │16 │17 │   │18 │19 │20 │21 │22 │23 │
├───┼───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┼───┤
│24 │25 │26 │27 │28 │29 │   │30 │31 │32 │33 │34 │35 │
╰───┴───┴───┴───┼───┼───┤   ├───┼───┼───┴───┴───┴───╯
                │36 │37 │38 │   │39 │40 │41 │
                ╰───┴───┴───╯   ╰───┴───┴───╯
```

### Base Layer Key Names (DEF)

```
╭─────┬───┬───┬───┬───┬───╮   ╭───┬───┬───┬───┬───┬─────╮
│ TAB │ Q │ W │ E │ R │ T │   │ Y │ U │ I │ O │ P │BKSP │
├─────┼───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┼─────┤
│LSHFT│ A │ S │ D │ F │ G │   │ H │ J │ K │ L │ ; │  '  │
├─────┼───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┼─────┤
│LCTRL│ Z │ X │ C │ V │ B │   │ N │ M │ , │ . │ / │RSHFT│
╰─────┴───┴───┼───┼───┼───┤   ├───┼───┼───┼───┴───┴─────╯
              │GUI│MO1│SPC│   │RET│MO2│ALT│
              ╰───┴───┴───╯   ╰───┴───┴───╯
```

### Common Position References

| Keys | Positions | Notes |
|------|-----------|-------|
| U + I | 7, 8 | Right hand, top row - used for LGUI combo |
| J + K | 19, 20 | Right hand, home row - used for ESC combo |
| L + D | 21, 15 | Cross-hand combo (removed - was DELETE) |
| RSHFT | 35 | Bottom-right key |

## Gotchas

### Board Name (ZMK Compatibility)

ZMK now requires `nice_nano@2.0.0` instead of `nice_nano_v2` in `build.yaml`. If builds fail with "Invalid BOARD", check this first.

### macOS Flashing Errors

The error `OSError: [Errno 5] Input/output error` during flashing is **normal on macOS**. The keyboard reboots before the OS confirms the write completed. The flash usually succeeded.

### Combo Syntax

```c
combo_name {
    bindings = <&kp KEYCODE>;  // or <&macro_name>
    key-positions = <POS1 POS2>;
};
```

### Hold-Tap vs Momentary Layer

- `&lt LAYER KEY` - Hold for layer, tap for key (can cause accidental key presses)
- `&mo LAYER` - Momentary layer only, no tap behavior (cleaner)

## Workflow

1. Edit `config/corne.keymap`
2. Commit and push to `main`
3. Wait for GitHub Actions build to complete
4. Run `./install.sh` to flash both halves
