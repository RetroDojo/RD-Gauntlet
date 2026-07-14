# RD-Gauntlet Virtual Gamepad Module

This folder adds reusable `adb shell uinput` automation for Android emulator/controller benchmark flows.

## Files

- `rdg_virtual_gamepad.py` - Python API + CLI (`register-gamepad`, `press-button`, `press-sequence`, `set-axis`, `unregister`, `probe-schema`)
- `device-profiles.json` - per-device profile config (serial/product match, VID:PID mimic, schema, quirks)
- `preflight_validate.py` - pre-flight checklist script with explicit READ-ONLY / SAFE-REGISTER / LIVE gating
- `sequences\sample-menu-sequence.json` - example sequence payload

## Architecture

`VirtualGamepadSession` opens `adb -s <serial> shell uinput -` and streams newline-delimited JSON command objects.

- Register happens once at session start.
- Button and axis operations emit `inject` event triplets.
- Cleanup is guaranteed by context manager (`with ... as session:`). Closing stdin tears down the virtual device (ephemeral lifecycle).

## Schema variance handling

Two schema variants are supported:

1. **symbolic** (newer CTS docs): tokens like `EV_KEY`, `BTN_SOUTH`, `UI_SET_KEYBIT`
2. **numeric-string** (older reader): tokens must be numeric values encoded as strings (`"1"`, `"304"`, `"101"`)

Auto handling:

- Profile schema can be `symbolic`, `numeric`, or `auto`.
- In `auto`, the module performs a SAFE-REGISTER probe:
  - tries symbolic register+sync
  - checks output for parse-failure markers (`Encountered malformed data`, `Invalid key in device configuration`, etc.)
  - falls back to numeric probe if needed

### Why probe is used

There is no reliable fully read-only feature flag exposed by `uinput` that declares parser schema. The reader implementation in discovery artifacts shows values are parsed via `nextString()` + `Integer.decode()`, which explains numeric-string requirements on older builds.

## Device profiles

Edit `device-profiles.json` to add new handhelds without code changes.

Example:

```json
{
  "id": "retroid-pocket-5",
  "match": { "serial": "ABC123", "product_name": "RetroidPocket5" },
  "display_name": "Retroid Controller (Virtual)",
  "vid": "0x18d1",
  "pid": "0xabcd",
  "schema": "auto",
  "quirks": { "default_hold_ms": 120, "default_inter_event_ms": 80 }
}
```

## CLI usage

From repo root:

```powershell
python .\virtual-gamepad\rdg_virtual_gamepad.py probe-schema --serial 97b7c783
python .\virtual-gamepad\rdg_virtual_gamepad.py register-gamepad --serial 97b7c783 --keep-alive-ms 1500
python .\virtual-gamepad\rdg_virtual_gamepad.py press-button --serial 97b7c783 A --hold-ms 120 --inter-event-ms 80
python .\virtual-gamepad\rdg_virtual_gamepad.py set-axis --serial 97b7c783 LX -1.0
python .\virtual-gamepad\rdg_virtual_gamepad.py press-sequence --serial 97b7c783 --sequence-file .\virtual-gamepad\sequences\sample-menu-sequence.json
python .\virtual-gamepad\rdg_virtual_gamepad.py unregister
```

`unregister` is a documented no-op for stateless CLI invocations; real cleanup happens automatically when each command closes session stdin.

## Pre-flight checklist script

```powershell
python .\virtual-gamepad\preflight_validate.py --serial 97b7c783
```

Behavior:

- **READ-ONLY always**: adb visibility, product lookup, `uinput --help`, `getevent -p`, profile resolution
- **SAFE-REGISTER always**: schema probe register+immediate teardown (no app-targeted input)
- **LIVE only with `--live`**: actual button injection round-trip

## Known limitations / guidance

- Even with correct schema, some apps ignore generic InputManager-routed virtual controllers.
- Inject too quickly and some apps/menus may drop events. Use profile delay knobs (`default_hold_ms`, `default_inter_event_ms`).
- Session is process-scoped; persistent daemon mode is intentionally not used yet to reduce stale-device risk.
- For unknown devices, if auto probe is inconclusive, set `schema` explicitly in the profile.

