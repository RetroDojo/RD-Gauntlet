# RD Gauntlet

> New to ADB, PowerShell, or Android device setup? Start with **[`NEWBIE-GUIDE.md`](./NEWBIE-GUIDE.md)** first. It is the step-by-step version for first-time users.

Reusable, device-agnostic ADB-driven hardware test orchestration for RetroDojo Android handheld reviews. The suite launches apps, captures screenshots, logs telemetry with `telemetry-monitor.sh`, saves frame/power diagnostics, records a short cooldown phase, and produces a Markdown report.

Formerly `tooling/device-bench-suite` inside `GammaOSNext-RPC-Port`, spun out into its own repo as the tooling grew beyond a single device port.

## Prerequisites

- Windows PC with `adb` available in `PATH`
- USB debugging enabled on the Android device
- Device authorized for ADB
- PowerShell execution allowed for local scripts (for example: `powershell -ExecutionPolicy Bypass -File ...`)
- `telemetry-monitor.sh` present in this folder (the orchestrator pushes it to `/data/local/tmp/telemetry-monitor.sh`)

## Files

- `devices.json` - named devices and optional pinned ADB serials
- `apps.json` - config-driven app list
- `Invoke-BenchmarkSuite.ps1` - main runner
- `New-BenchReport.ps1` - standalone report generator
- `telemetry-monitor.sh` - device-side sampler (already validated separately)
- `storage-speed-test.sh` - `/sdcard` sequential read/write throughput probe (optional)
- `wifi-throughput-test.sh` - HTTP download throughput probe using on-device `curl` (optional)
- `haptic-intensity-check.sh` - pure-ADB haptics feasibility probe (optional, may report unsupported)
- `perfetto-surfaceview-fps.sh` + `Parse-PerfettoSurfaceFps.py` - Perfetto capture + host parser prototype (optional)
- `Invoke-StickDriftCheck.ps1` - manual idle analog drift checker (standalone helper)
- `New-ComparisonDataset.ps1` - rebuilds long-format cross-run/cross-device comparison dataset
- `New-ComparisonCharts.ps1` - generates first-pass comparison charts from the dataset
- `Analyze-Screenshot.py` - single screenshot visual/color/sharpness analysis JSON
- `Compare-Screenshots.py` - pairwise screenshot comparison (SSIM + color/sharpness deltas)
- `Invoke-VisualAnalysis.ps1` - optional standalone wrapper for analysis/comparison runs

## Comparison dataset + charts (Phase 1)

For cross-run/cross-device aggregation and baseline chart generation, see:

- [`README-comparison-dataset.md`](./README-comparison-dataset.md)

## Configure devices

`devices.json` is an array so you can keep multiple handhelds ready:

```json
[
  {
    "name": "RPC6",
    "adbSerial": "MC94516AQF051901944",
    "notes": "Retroid Pocket Classic 6 reference device"
  },
  {
    "name": "FutureHandheld",
    "notes": "Leave adbSerial empty to auto-detect the sole connected device"
  }
]
```

Rules:

- If `adbSerial` is present, the suite targets that exact device.
- If `adbSerial` is empty/omitted, the suite auto-detects the **single** connected device.
- If zero or multiple devices are connected and no serial is pinned, the suite errors clearly instead of guessing.

## Configure apps

`apps.json` is also an array:

```json
{
  "name": "PPSSPP",
  "package": "org.ppsspp.ppsspp",
  "type": "game",
  "durationSec": 120,
  "monkeyEnabled": true,
  "monkeyPctTouch": 70,
  "monkeyPctMotion": 20,
  "notes": "Meaningful load still depends on game content already running."
}
```

Recommended conventions:

- `type: "benchmark"` for apps like 3DMark / Geekbench
- `type: "game"` for emulators, games, and real-world load tests
- `durationSec: 180` for benchmark-style runs
- `durationSec: 120` for game-style runs
- `monkeyEnabled: true` only when monkey input is acceptable for that app
- `capturePerfetto`, `captureStorageSpeed`, `captureWifiThroughput`: optional per-app captures (default `false`)
- `perfettoDurationSec`: short capture window for Perfetto prototype (default `15`)
- `launchIntent`: optional explicit launch definition used with `adb shell am start ...` before telemetry/monkey loop

`launchIntent` example (direct ROM open, when the app supports `ACTION_VIEW`):

```json
{
  "name": "DraStic",
  "package": "com.dsemu.drastic",
  "type": "game",
  "durationSec": 120,
  "monkeyEnabled": true,
  "launchIntent": {
    "action": "android.intent.action.VIEW",
    "dataUri": "file:///storage/emulated/0/ROMs/nds/SonicRush.zip",
    "type": "*/*",
    "component": "com.dsemu.drastic/.DraSticActivity"
  }
}
```

When `launchIntent` is not present, the suite keeps the existing launcher behavior (`monkey -p <pkg> -c android.intent.category.LAUNCHER 1`) for backward compatibility.

`devices.json` supports suite-level optional flags:

- `checkStickDrift` (manual idle check; default `false`)
- `sampleHaptics` (best-effort rumble probe; default `false`)
- `capturePerfetto`, `captureStorageSpeed`, `captureWifiThroughput` (device defaults for all apps)

## Test content pipeline (new)

Use these helpers to stage real game content from your local libraries (outside git):

- `test-content.json` - curated `(system, romPath, devicePath)` entries from `D:\ROMS\...`
- `Push-TestContent.ps1` - pushes content via ADB, checks `/storage/emulated/0` free space, and skips large files when space is insufficient
- `test-content-matrix.md` - curated “intense” title rationale + blocked/gap tracking

Example:

```powershell
.\Push-TestContent.ps1 -DeviceName RG476H -Systems nds,n64
```

### BIOS convention for future systems

For PS1/PS2/GameCube/Dreamcast BIOS, keep dumps in the existing flat folder:

- `D:\bios\`

`Push-TestContent.ps1` maps known filenames automatically:

- PS1: `scph*.bin`
- PS2: `ps2-*.bin`
- Dreamcast: `dc_boot.bin`, `dc_flash.bin`, `dc_nvmem.bin`
- GameCube: `IPL.bin`

Matches are pushed to `/storage/emulated/0/ROMs/bios/<system>/` (and PS1/Dreamcast are also mirrored to `/storage/emulated/0/RetroArch/system/` for RetroArch usage). If no system match is found, it logs `BIOS not found, skipping`.

## Run the suite

Target a named device from `devices.json`:

```powershell
.\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6
```

Auto-detect the sole connected device:

```powershell
.\Invoke-BenchmarkSuite.ps1
```

The suite automatically mutes device volume before running (audio isn't evaluated by
any test) and, at the end (or on failure, via a script-level `trap`), restores the
device's original brightness/auto-brightness mode/volume and returns to the home
screen. Pass `-MuteAudio $false` to skip muting if you need to hear the device during
a run. This "restore defaults" step is best-effort (settings-only, no partition/vendor
writes) — always visually confirm the device looks normal after a long unattended run.

Use a custom apps config: 

```powershell
.\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6 -AppsConfig .\apps.json
```

Drive benchmark apps manually while telemetry still logs:

```powershell
.\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6 -SkipMonkey
```

Results default to:

```text
.\results\<timestamp>\<deviceName>\
```

Each app gets its own folder containing:

- `00-launch.png`
- `99-end.png`
- `telemetry.csv`
- `cooldown.csv`
- `framestats.txt`
- `batterystats.txt`
- `battery-snapshot.txt`
- optionally: `storage-speed.json`, `wifi-throughput.json`, `perfetto-fps.json`, `perfetto-trace.perfetto-trace`

Suite root may also include:

- `stick-drift.json` (if `checkStickDrift` enabled)
- `haptic-intensity.json` (if `sampleHaptics` enabled)

## Generate or regenerate a report

The main suite calls the report generator automatically, but you can rerun it later:

```powershell
.\New-BenchReport.ps1 -OutDir .\results\20260707-170000\RPC6
```

`report.md` includes:

- top-level device baseline info (`ro.product.model`, Android version, build fingerprint, `wm size`, baseline battery level)
- per-app telemetry summary tables (dynamic columns; no metric names are hardcoded)
- cooldown telemetry summary tables
- linked screenshots and raw diagnostic artifacts
- best-effort frame timing summary from `dumpsys gfxinfo ... framestats`
- optional storage/WiFi/Perfetto result tables when those artifacts exist

## Optional visual screenshot analysis (new)

This is an opt-in post-processing capability (not auto-run by `Invoke-BenchmarkSuite.ps1`) for assessing final on-screen image characteristics from saved screenshots.

### Single screenshot analysis

```powershell
python .\Analyze-Screenshot.py .\results\rg476h-emulator-batch\DraStic\00-launch.png --out-json .\results\visual-analysis\drastic-launch.json
```

Outputs JSON with:

- screenshot resolution + aspect ratio
- panel/context info when nearby `device-info.json` exists (for example parsed `wmSize`)
- average RGB + per-channel mean/std + coarse 16-bucket histograms
- Laplacian-variance sharpness score
- banding/posterization heuristic indicators

### Pairwise screenshot comparison

```powershell
python .\Compare-Screenshots.py .\results\full-validation-retroarch\RetroArch\00-launch.png .\results\full-validation-rg476h\RetroArch\00-launch.png --out-json .\results\visual-analysis\retroarch-cross-device.json --out-md .\results\visual-analysis\retroarch-cross-device.md
```

Outputs JSON + Markdown summary with:

- SSIM (uses `scikit-image` when available; otherwise manual Gaussian-window fallback)
- average RGB channel deltas (`B - A`)
- sharpness delta (`B - A`) from Laplacian variance
- human-readable interpretation (for example warmer/cooler, sharper/blurrier wording)

### PowerShell wrapper shortcuts

Analyze launch+end screenshots for one app run:

```powershell
.\Invoke-VisualAnalysis.ps1 -RunDir .\results\rg476h-emulator-batch -AppName DraStic
```

Cross-run comparison for the same app shot name:

```powershell
.\Invoke-VisualAnalysis.ps1 -RunDirA .\results\full-validation-retroarch -RunDirB .\results\full-validation-rg476h -CrossAppName RetroArch -ShotName 00-launch.png
```

### Scope and limitation (important)

- Raw Android `screencap` captures the **final composited panel-resolution frame**.
- That means this tooling can quantify **final on-screen** color/contrast/sharpness differences.
- It **cannot directly prove internal emulator render resolution or upscale filter** choice from screencap alone; use wording accordingly in reports.

## Framestats parsing notes

`New-BenchReport.ps1` is intentionally defensive because `dumpsys gfxinfo <package> framestats` varies by Android version:

- On the reference RPC6 / Android 14 device, the observed output included summary lines such as `Total frames rendered:` and `Janky frames:` but did **not** always include raw `---PROFILEDATA---` frame rows.
- On other Android builds, raw comma-separated framestats rows may be present with columns like `IntendedVsync`, `Vsync`, and `FrameCompleted`.
- The parser first tries to read summary values directly.
- If raw frame rows exist, it computes a naive FPS estimate from average frame duration.
- If raw rows are absent, it falls back to `Total frames rendered / configured durationSec`.
- Parse failures are reported as notes in `report.md`; they are not fatal.

## Known limitations / not fully automated

This suite is intentionally honest about what monkey automation can and cannot do:

- `monkey` is useful for unattended stress, thermals, background load variation, and keeping activity inside a specific package.
- `monkey` does **not** reliably find or press a benchmark app's real **Start Test** button across arbitrary UI layouts, screen sizes, launchers, dialogs, or app updates.
- For **official 3DMark / Geekbench scores**, prefer `-SkipMonkey` and tap through the benchmark flow manually while telemetry logs in the background.
- For emulator/game testing, monkey can keep UI activity alive, but meaningful gameplay load still depends on content already loaded inside the emulator/game.
- Direct intent launch support is app-specific: on RG476H we confirmed `ACTION_VIEW` patterns for DraStic and Mupen64PlusFZ; RetroArch (`com.retroarch.aarch64`) currently exposes only MAIN/launcher in resolver output and did not auto-open PSX content via tested explicit VIEW launch.
- Dreamcast/Flycast remains blocked in this workflow while `D:\ROMS\dc` is empty (and requires user-owned content + BIOS dumps).
- BIOS availability is no longer the blocker for PS1/PS2/GameCube/Dreamcast in this environment (`D:\bios` is populated); current blockers are emulator/core availability (PS1 RetroArch load-core list did not show a PlayStation core on this RG476H state, no standalone PS2/GameCube emulator APK installed) plus missing Dreamcast ROM content.
- `dumpsys batterystats --charged <package>` may be sparse or empty on unrooted / non-privileged builds.
- WiFi throughput is internet-path dependent (CDN/ISP variability), not a pure local-link test.
- Storage read throughput can be cache-influenced without root cache-drop.
- Stick-drift check is manual: **do not touch the controller** during the sampling countdown/window.
- Pure-ADB haptic intensity may be unsupported if `cmd vibrator` is unavailable to shell UID or live accelerometer samples are inaccessible.
- Telemetry column names vary by device because `telemetry-monitor.sh` discovers CPU/GPU/fan/battery/thermal nodes dynamically at runtime.
- Some devices expose no fan node, no GPU busy counter, or vendor-specific thermal names; the report preserves whatever the device actually exposed.

If `automation-research-findings.md` appears in this folder later, treat it as a companion document for app-specific automation research beyond generic monkey launching/stress behavior.

## Scaling recommendations

- Keep every handheld in `devices.json` with a stable `name` and, when possible, a pinned `adbSerial`.
- Charge devices to a consistent baseline before runs.
- Standardize environmental conditions (ambient temperature, charger connected/disconnected state, fan profile, case on/off).
- Leave the 15-second cooldown enabled so back-to-back app sections capture recovery behavior consistently.
- For truly unattended, score-valid benchmark automation, you will likely need app-specific UI automation research per benchmark app and possibly per Android version/device skin.
