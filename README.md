# Android Device Bench Suite

Reusable, device-agnostic ADB-driven hardware test orchestration for RetroDojo Android handheld reviews. The suite launches apps, captures screenshots, logs telemetry with `telemetry-monitor.sh`, saves frame/power diagnostics, records a short cooldown phase, and produces a Markdown report.

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

`devices.json` supports suite-level optional flags:

- `checkStickDrift` (manual idle check; default `false`)
- `sampleHaptics` (best-effort rumble probe; default `false`)
- `capturePerfetto`, `captureStorageSpeed`, `captureWifiThroughput` (device defaults for all apps)

## Run the suite

Target a named device from `devices.json`:

```powershell
.\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6
```

Auto-detect the sole connected device:

```powershell
.\Invoke-BenchmarkSuite.ps1
```

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
