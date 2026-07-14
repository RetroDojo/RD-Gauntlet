# RD-Gauntlet Review B-roll Pipeline

PowerShell pipeline for scripted emulator setting permutations + short clip capture + ffmpeg comparison grid output.

## What this adds

- Settings-matrix JSON format (`settings-matrix.schema.json`)
- Emulator config patcher strategy module (`ConfigPatcher.psm1`)
  - **Fully implemented:** RetroArch (`retroarch.cfg` + `retroarch-core-options.cfg`)
  - **Stubbed/TODO:** DuckStation, Flycast, AetherSX2 key mapping + file locations
- Capture orchestrator (`Invoke-BrollCapture.ps1`)
  - Patch settings per permutation
  - Restart emulator app
  - RetroArch scene reproducibility via NCI `LOAD_STATE_SLOT <n>`
  - Record fixed-duration clips with `scrcpy --no-playback --no-window --time-limit`
  - Emit per-clip manifest JSON (settings, serial, timestamp, GPU metadata)
- Post-processor (`New-BrollComparisonGrid.ps1`)
  - Reads manifests
  - Adds drawtext labels
  - Builds 2/3/4-up comparison MP4 via `hstack`/`xstack`
- Single entry point (`Run-BrollComparisonJob.ps1`)

## Prerequisites

On host PATH:

- `adb`
- `scrcpy`
- `ffmpeg`

Scripts hard-fail with clear errors if any are missing.

## Matrix file format

Use JSON; validate against `settings-matrix.schema.json`.

Top-level fields:

- `jobName` (string)
- `outputRoot` (optional output base path)
- `clipDurationSec` (default 12)
- `device.serial` (optional; otherwise pass `-DeviceSerial` or auto-detect one connected device)
- `target`
  - `emulator`: `retroarch | duckstation | flycast | aethersx2`
  - `package`: Android package name
  - `paths` (RetroArch paths override)
  - `scene`
    - `type: "retroarch_nci_state_slot"` + `slot` for RetroArch reproducible scene load
    - other emulators currently use TODO placeholders
  - `launch.intent` (optional explicit `am start` values)
- `permutations[]`
  - `id` (required)
  - `label` (used for overlay text)
  - `overrides`
    - `retroarchCfg`: key/value pairs in `retroarch.cfg`
    - `coreOptions`: key/value pairs in RetroArch core options cfg
    - emulator-specific override sections for non-RetroArch are accepted but currently stubbed

Example: `examples\retroarch-vulkan-vs-gl.matrix.json`

## Usage

Dry-run (safe review, no device writes/app control/recording):

```powershell
.\broll-pipeline\Run-BrollComparisonJob.ps1 `
  -MatrixPath .\broll-pipeline\examples\retroarch-vulkan-vs-gl.matrix.json `
  -DryRun
```

Live run (when device is available for active testing):

```powershell
.\broll-pipeline\Run-BrollComparisonJob.ps1 `
  -MatrixPath .\broll-pipeline\examples\retroarch-vulkan-vs-gl.matrix.json `
  -DeviceSerial 97b7c783
```

## Strategy pattern notes

`ConfigPatcher.psm1` routes by emulator key:

- `retroarch`: real patch implementation for:
  - `video_driver`
  - `video_smooth`
  - `video_scale_integer`
  - and any additional `retroarchCfg`/`coreOptions` keys passed in matrix
- `duckstation`, `flycast`, `aethersx2`: explicit no-op strategy stubs with TODO logging.
  - Needed later: discover config files, define stable key map, implement pre-staged-save scene restore.

## Save-state reproducibility

- RetroArch: NCI UDP command over adb shell:
  - `LOAD_STATE_SLOT <n>` to restore identical scene before each clip.
- Other emulators:
  - Intended approach is pre-stage a known save-state file in app storage and trigger load.
  - Current implementation logs TODO and performs no scene load action.

## Outputs

Each run creates:

- `clips\*.mp4`
- `manifests\*.manifest.json`
- `captures-index.json`
- `<jobName>_comparison.mp4` (unless `-SkipPostProcess`)

Manifests include read-only GPU metadata (`getprop` + `dumpsys SurfaceFlinger` snippet) for driver context tagging.
