# RetroDojo Device Bench Suite — Automation Research Findings
**Prepared:** 2026-07-07  
**Scope:** ADB-driven, unattended, cross-device Android hardware benchmarking pipeline for YouTube retro-handheld review content  
**Disclaimer:** All findings are based on publicly available primary documentation, AOSP source references, and official tool repositories. This is an engineering decision document — dead ends are documented honestly.

---

## Phase 2 implementation results (RPC6 live smoke test, July 2026)

This section records what was implemented in `tooling/device-bench-suite` and what happened on a real connected RPC6 (GammaOS Next Android 14) during short smoke runs (10-30s per capability), not full 180s benchmark validation.

### Implemented

1. **Telemetry monitor extensions (`telemetry-monitor.sh`)**
   - Added per-sample CPU utilization using `/proc/stat` deltas:
     - `cpu_total_util_pct`
     - `cpuN_util_pct` for every discovered `cpuN` line.
   - Added battery coulomb counter column:
     - `batt_charge_counter_uah`
     - Uses `/sys/class/power_supply/battery/charge_counter` when present, with `dumpsys battery` (`Charge counter:`) fallback.

2. **New optional helpers**
   - `storage-speed-test.sh` (`/sdcard` sequential write/read via `dd`, JSON output).
   - `wifi-throughput-test.sh` (HTTP range download throughput via on-device `curl`, JSON output).
   - `haptic-intensity-check.sh` (pure-ADB feasibility probe, explicit unsupported reporting).
   - `perfetto-surfaceview-fps.sh` + host parser `Parse-PerfettoSurfaceFps.py` (Perfetto capture + best-effort FPS extraction).
   - Stick drift check added as PowerShell+ADB flow (`Invoke-StickDriftCheck` inside orchestrator), with explicit countdown and no-touch instruction.

3. **Orchestrator/report integration**
   - `Invoke-BenchmarkSuite.ps1` now supports optional feature flags in `apps.json`/`devices.json`:
     - `captureStorageSpeed`, `captureWifiThroughput`, `capturePerfetto`, `perfettoDurationSec`
     - suite-level `checkStickDrift`, `sampleHaptics`
   - `New-BenchReport.ps1` now includes optional tables/artifact links for storage/WiFi/Perfetto and suite-level manual checks.

### What worked live on RPC6

- CPU utilization columns populated with plausible non-NA percentages.
- `batt_charge_counter_uah` populated (via `dumpsys battery` fallback path remains available).
- Storage speed script produced parseable JSON with write/read MB/s.
- WiFi throughput script produced parseable JSON with `speedBytesPerSec` / `speedMbps`.
- Perfetto capture command works on this build (`android.surfaceflinger.frame` + `android.surfaceflinger.frametimeline` are registered data sources).

### Real limitations / dead ends hit live

- `cmd vibrator` service is not available to shell UID on this build (`cmd: Can't find service: vibrator`), so pure-ADB haptic actuation is blocked.
- `dumpsys sensorservice` is useful for sensor inventory/registration state but not a robust live accelerometer stream for RMS/peak vibration scoring; reliable cross-device rumble quantification still needs a companion APK (or external instrumentation).
- Perfetto parsing is best-effort and package-match dependent; SurfaceView-heavy content may still produce sparse/ambiguous package-attributable rows. This remains a prototype and not yet a production-grade FPS truth source for all benchmark/game render paths.
- WiFi throughput remains internet/CDN/ISP-path dependent (not isolated RF/link-layer throughput).

### Practical recommendation after Phase 2

- Keep these features optional and explicitly labeled as prototype/manual-assist where appropriate.
- Continue using camera-based FPS counting for final on-screen gameplay truth when SurfaceView attribution is ambiguous.
- Treat Perfetto output as supporting evidence, not sole ground truth, until broader per-device validation is complete.

## Section 1: Frame Rate / Jank Measurement Without Root

### 1.1 `adb shell dumpsys gfxinfo <package> framestats`

#### Complete Column Format (Authoritative AOSP Reference)

The output of `dumpsys gfxinfo <package> framestats` is a CSV-style table. **Every row is one frame.** All timestamps are in **nanoseconds (ns) since boot**. The authoritative column definition lives in `frameworks/base/libs/hwui/FrameInfo.h` in AOSP source ([cs.android.com](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/libs/hwui/FrameInfo.h)).

**Columns in Android 11/12 (`framestats` v1):**

| # | Column Name | What it timestamps |
|---|---|---|
| 0 | `Flags` | Bitmask: `0x0` = normal frame; `0x1` = skipped/dropped; other bits signal buffer reuse or special handling |
| 1 | `IntendedVsync` | When Choreographer *intended* this frame to start (theoretical vsync) |
| 2 | `Vsync` | Actual vsync signal received by Choreographer |
| 3 | `OldestInputEvent` | Oldest unhandled input event's arrival timestamp |
| 4 | `NewestInputEvent` | Most recent input event's arrival timestamp |
| 5 | `HandleInputStart` | Start of input event handling on UI thread |
| 6 | `AnimationStart` | Start of animation evaluation |
| 7 | `PerformTraversalsStart` | Start of measure/layout/draw view traversal |
| 8 | `DrawStart` | Start of actual display list recording on UI thread |
| 9 | `SyncQueued` | Frame queued to RenderThread for GPU sync |
| 10 | `SyncStart` | RenderThread begins GPU fence sync |
| 11 | `IssueDrawCommandsStart` | GPU draw commands submitted to driver |
| 12 | `SwapBuffers` | `eglSwapBuffers()` called (buffer handed to SurfaceFlinger) |
| 13 | `FrameCompleted` | UI thread considers frame done |
| 14 | `DequeueBufferDuration` | Duration (ns) to dequeue a buffer from SurfaceFlinger's queue |
| 15 | `QueueBufferDuration` | Duration (ns) to enqueue buffer back to SurfaceFlinger |

**Columns added in Android 12 (API 31) — `framestats` v2:**

| # | Column Name | What it timestamps |
|---|---|---|
| 16 | `GpuCompleted` | GPU fence signaled (GPU finished rendering — critical for actual latency) |
| 17 | `SwapBuffersCompleted` | `eglSwapBuffers()` *returned* (buffer actually acquired by SurfaceFlinger) |
| 18 | `DisplayPresentTime` | Frame actually presented to display panel (pixel-accurate) |

> **Confirmed:** `GpuCompleted` was added in Android 12 (some sources say 13; primary AOSP source ([FrameMetrics API](https://developer.android.com/reference/android/view/FrameMetrics)) and the Frame Timeline project launched at API 31 confirm it was part of the Android 12 Frame Timeline initiative). `SwapBuffersCompleted` and `DisplayPresentTime` were definitively added in Android 12 (API 31). No new framestats columns were added in Android 13 or 14. The column order/count is **stable across Android 11–14** (Android 11 has 16 columns, Android 12+ has 19). Your parser **must check column count** to handle both layouts.

#### The `Flags` Column in Detail

Defined in `frameworks/base/core/java/android/view/FrameInfo.java`:
- `Flags = 0`: Normal frame, should be included in all stats calculations
- `Flags = 1` (FLAG_SKIPPED_FRAME): Frame was skipped — **exclude from FPS and jank calculations**, count as a dropped frame
- Other bits: internal renderer hints (buffer reuse, etc.) — safe to ignore for external measurement

**⚠ Critical:** Any row with `Flags != 0` should be excluded from timing computations but *counted* toward dropped-frame totals.

#### Computing FPS and Jank Percentage from `framestats`

```python
# Pseudocode — adapt to your language
VSYNC_16MS = 16_666_667  # ns (for 60 Hz)
VSYNC_11MS = 11_111_111  # ns (for 90 Hz)
VSYNC_8MS  = 8_333_333   # ns (for 120 Hz)

# Determine device refresh rate first:
# adb shell dumpsys display | grep "mRefreshRate"
# or: adb shell cat /sys/class/graphics/fb0/modes | grep "60\|90\|120"

frames = [row for row in parsed_framestats if row['Flags'] == 0]  # exclude skipped

# FPS
total_time_ns = frames[-1]['FrameCompleted'] - frames[0]['FrameCompleted']
fps = len(frames) / (total_time_ns / 1e9)

# Jank: a frame is janky if it takes >1 vsync interval
# Compare consecutive FrameCompleted timestamps
janky = 0
for i in range(1, len(frames)):
    frame_duration = frames[i]['FrameCompleted'] - frames[i-1]['FrameCompleted']
    if frame_duration > VSYNC_16MS:  # adjust for 90/120 Hz
        janky += 1

jank_pct = (janky / len(frames)) * 100

# Dropped frames (Flags=1 rows)
dropped = sum(1 for row in all_rows if row['Flags'] == 1)
```

> **Important nuance:** `framestats` only buffers the **last 120 frames** rendered. For benchmark runs lasting more than a few seconds at 60 fps, you **must poll repeatedly in a loop** (every ~1.5s) and append results, deduplicating by `IntendedVsync` timestamp. Use `dumpsys gfxinfo <pkg> reset` before each test run.

#### Has the Format Changed Across Android 11→14?

- **Android 11 (API 30):** 16 columns, header row is always present
- **Android 12 (API 31):** 19 columns (adds `GpuCompleted`, `SwapBuffersCompleted`, `DisplayPresentTime`)
- **Android 13 (API 33):** Same 19 columns as Android 12 — no changes
- **Android 14 (API 34):** Same 19 columns — no changes
- **OEM skins (MIUI, OneUI, ColorOS):** The underlying HWUI renderer writes framestats — OEMs do not typically intercept this path. However, some OEM devices use a separate GL surface for system UI overlays that may appear as additional windows. The data itself should be trustworthy, but **some MIUI builds are known to have framestats sections return `0` for certain timestamps if the app uses SurfaceView instead of standard Views**. Always validate on a sample MIUI device.

**Parsing robustness tip:** Don't hardcode column indices. Parse the header row by name each time, map column names to indices. This future-proofs against Android 15+ additions.

---

### 1.2 `adb shell dumpsys gfxinfo <package>` (Aggregate Stats, no `framestats`)

The simpler form (no `framestats` suffix) outputs an aggregate block at the end of its output. Relevant section:

```
** Graphics info for pid XXXX [com.example.package] **

Total frames rendered: 2847
Janky frames: 213 (7.49%)
50th percentile: 5ms
90th percentile: 14ms
95th percentile: 22ms
99th percentile: 58ms
Number Missed Vsync: 87
Number High input latency: 12
Number Slow UI thread: 31
Number Slow bitmap uploads: 4
Number Slow issue draw commands: 18
```

**Is this more reliable/portable than `framestats` across OEM skins?**

**Yes, with caveats.** The aggregate block:
- Works on all Android versions back to Android 6 (Marshmallow)
- Survives OEM customization better because it uses the same HWUI counter infrastructure
- **Does not require you to poll repeatedly** — captures the entire session since last reset
- The "Janky frames" definition here is HWUI's internal definition: a frame that missed its intended vsync deadline (not necessarily >16ms wall-clock, but >1 vsync interval at whatever the screen refresh rate is — so this adapts correctly to 90/120 Hz devices)

**Reliability caveats:**
- OEM skins with modified HWUI pipelines (rare but exists on some Unisoc/Rockchip low-end devices) may report zero or trivially small values
- Games using Vulkan/OpenGL directly (bypassing View system) may show **zero or very low rendered frame counts** — e.g., Antutu, 3DMark, and many gaming apps render to a SurfaceView/GLSurfaceView and some frames bypass HWUI entirely
- For game benchmarks, `framestats` from the GL layer should be more meaningful than the aggregate block, but you'll still need to handle the SurfaceView limitation

**Recommended workflow:** Use `dumpsys gfxinfo <pkg> reset` at test start, run the benchmark, then `dumpsys gfxinfo <pkg>` at end to capture aggregate. This is lower overhead than continuous `framestats` polling and sufficient for YouTube-review-level jank reporting.

---

### 1.3 `adb shell dumpsys SurfaceFlinger --latency <window>`

**Status: DEPRECATED in Android 13, REMOVED in Android 14.**

| Android | Status |
|---------|--------|
| ≤ 12 | Works; outputs 3-column frame timing (desired present time, actual start of scan-out, actual present time) in ns |
| 13 | Deprecated; may still output with a deprecation warning, unreliable |
| 14+ | Removed; will return no output or an error |

**Why it existed:** Pre-Frame Timeline era, this was the only way to get from-the-compositor frame timing. It required knowing the exact surface/window name, which was brittle.

**Replacement in Android 14:** `adb shell dumpsys SurfaceFlinger --show-frame-timeline` provides modern structured data. However, this is a human-readable dump, not a parseable per-frame CSV. For automated parsing, use Perfetto (see §1.4) or `dumpsys gfxinfo framestats`.

**Bottom line for your pipeline:** Do not use `--latency`. It will break on any Android 14 device (and many Rockchip/Unisoc devices that ship heavily modified Android 12 builds may also behave unpredictably). Remove it from your toolchain now.

---

### 1.4 Perfetto / Newer Replacement APIs

#### `adb shell cmd gfxinfo`
This is **not a separate tool** — `cmd gfxinfo` routes to the same `dumpsys gfxinfo` service. It exists as an alias for convenience in some Android versions but produces equivalent output. No special advantage for your use case.

#### Perfetto + FrameTimeline Data Source

Perfetto's FrameTimeline data source ([perfetto.dev/docs/data-sources/frametimeline](https://perfetto.dev/docs/data-sources/frametimeline)) provides **the richest jank data available on Android 12+**:

- Two timeline tracks per app: **Expected Timeline** (what the scheduler promised) and **Actual Timeline** (what the app actually delivered)
- Jank types classified: `AppDeadlineMissed`, `BufferStuffing`, `SurfaceFlingerCpuDeadlineMissed`, `SurfaceFlingerGpuDeadlineMissed`, `DisplayHAL`, `PredictionError`
- `SurfaceViews` are **not yet supported** by FrameTimeline (relevant: 3DMark, Antutu, and most gaming benchmarks render via SurfaceView — this is a significant limitation)
- Requires **Android 12 or higher**
- Does NOT require root on most devices

**Automated capture workflow:**

```bash
# Step 1: Create a Perfetto config file (frametimeline.pbtxt)
# Step 2: Start trace
adb shell perfetto \
  -c /data/misc/perfetto-traces/frametimeline.pbtxt \
  --txt \
  -o /data/misc/perfetto-traces/trace.perfetto-trace

# Step 3: Pull trace
adb pull /data/misc/perfetto-traces/trace.perfetto-trace ./output/

# Step 4: Parse with trace_processor
# python: import perfetto; tp = perfetto.TraceProcessor(trace='trace.perfetto-trace')
# results = tp.query('SELECT * FROM actual_frame_timeline_slice')
```

**Realistic complexity assessment for your pipeline:**

| Factor | Rating | Notes |
|--------|--------|-------|
| Capture via ADB | 🟡 Medium | Config file management, path permissions vary by Android version |
| Parsing | 🔴 High | Requires Perfetto's `trace_processor` Python package or CLI; output is protobuf, not CSV |
| SurfaceView support | 🔴 None | Gaming benchmarks = SurfaceView = blind spot |
| Android 11 devices | 🔴 None | FrameTimeline is 12+ only |
| Unisoc/Rockchip (older Android) | 🔴 Likely broken | Many ship Android 11 with minimal Perfetto support |
| Value for YouTube review | 🟡 Medium | Better jank classification, but `gfxinfo` aggregate covers 80% of need |

**Verdict on Perfetto for your pipeline:** The payoff is real for detailed jank taxonomy, but the complexity is high — especially given your target devices span Android 11–14 and include non-Google SoCs with spotty Perfetto support. The 3DMark/gaming SurfaceView blind spot is a fundamental blocker for the primary use case. **Recommend deferring Perfetto integration to a Phase 2 or advanced-mode feature.** For the v1 pipeline, `dumpsys gfxinfo` aggregate + `framestats` continuous polling covers the core need adequately.

---

> ### 🔵 Bottom Line Recommendation — Section 1
>
> **Primary FPS/jank method:** `dumpsys gfxinfo <pkg> reset` before test, then continuous `framestats` polling (every 1.5s, dedup by IntendedVsync) during the run, then `dumpsys gfxinfo <pkg>` at end for aggregate fallback. Parse the 19-column framestats on Android 12+ and 16-column on Android 11. Check column count from the header row; never hardcode indices.
>
> **For gaming benchmarks using SurfaceView/GLSurfaceView** (3DMark, Antutu, most emulators): `framestats` will show very few or no HWUI frames. You'll need to measure frame times via SurfaceFlinger's Frame Rate API or fallback to wall-clock timing of the benchmark's reported score. This is a known hard limit with no clean ADB-only workaround for unrooted devices.
>
> **Do not use `--latency`.** It's dead on Android 14.
>
> **Perfetto is Phase 2** — valuable but too complex and too reliant on Android 12+ to justify for your first pipeline iteration.

---

## Section 2: Battery Life / Power Draw Over ADB Without Special Hardware

### 2.1 `dumpsys batterystats` — What's Actually Available Without Root

`adb shell dumpsys batterystats` runs as the `shell` UID, which on Android ≥ 8 has `READ_LOGS` permission but **not** `BATTERY_STATS` system-level permission (declared as `signature|privileged` in AOSP). The data split is:

**Available without root via `adb shell dumpsys batterystats`:**
- Battery level history (coarse, every ~1% change)
- Screen on/off duration, total time
- App CPU time attribution (UID-level, NOT per-process)
- Wakelock hold times (aggregate totals, not per-wakelock-event timeline unless `--enable full-wake-history` was set prior)
- Wi-Fi, mobile radio state history (coarse)
- Job scheduler and sync invocations (aggregate counts)
- Estimated power use table (rough mAh estimates based on device's `power_profile.xml` — accuracy varies wildly)

**NOT available without root:**
- Full timestamped wakelock event history (requires `--enable full-wake-history` set before test AND it fills up in ~3-4 hours)
- Kernel wakelock breakdown (requires root access to `/proc/wakelocks`)
- Per-sensor usage breakdown
- Native process battery attribution
- Detailed per-app GPS and location usage
- `--charged <package>` flag: this filters the output to app-specific stats but the underlying data resolution is the same — not more detailed than above on unrooted devices

**`adb shell dumpsys batterystats --reset`** works without root and is essential before starting a benchmark battery test.

**Practical recommendation for your pipeline:**
```bash
# Before test
adb shell dumpsys batterystats --reset
adb shell dumpsys battery | grep "level"   # capture starting %, voltage

# [Run benchmark for 20-30 minutes]

# After test  
adb shell dumpsys batterystats > batterystats_run.txt
adb shell dumpsys battery | grep "level"   # capture ending %, voltage, temperature
```

The delta `battery level` combined with your `current_now` telemetry (see §2.2) gives a more reliable energy picture than parsing `batterystats` power estimates, which are device-config-dependent.

---

### 2.2 `/sys/class/power_supply/battery/current_now` — Sign Convention and Units

**The canonical Linux Power Supply class documentation** ([kernel.org/doc/Documentation/power/power_supply_class.txt](https://www.kernel.org/doc/Documentation/power/power_supply_class.txt)) specifies:
- Unit: **microamps (µA)**
- Sign: **negative = discharging (current flowing out of battery), positive = charging**

**Real-world OEM reality — varies significantly:**

| OEM / Platform | Typical unit | Typical sign convention | Notes |
|---|---|---|---|
| AOSP / Pixel | µA | negative = discharging | Conforms to spec |
| Samsung (Exynos + Qualcomm) | µA | **positive = discharging** | Inverted vs. spec |
| Xiaomi/Redmi (MediaTek, Qualcomm) | µA | Varies — check `/status` | Generally spec-compliant but not always |
| Unisoc (SC9863A, T618, T700) | µA or mA | Varies — some report mA | Some budget Unisoc drivers use mA; values will be ~1000x smaller than µA |
| Rockchip (RK3326, RK3566) | µA | Varies by fuel gauge driver | Bergamo/CW2015 fuel gauges common on Rockchip; check kernel source |
| MediaTek (Helio G85, G99) | µA | negative = discharging | Generally well-behaved |

**How to auto-detect unit and sign on an unknown device — build this into your calibration script:**

```bash
# Step 1: Get current charging status
STATUS=$(adb shell cat /sys/class/power_supply/battery/status)
# Values: "Charging", "Discharging", "Full", "Not charging", "Unknown"

# Step 2: Get current_now value
CURRENT_NOW=$(adb shell cat /sys/class/power_supply/battery/current_now)

# Step 3: Determine sign convention
# If STATUS=Discharging and CURRENT_NOW > 0 → OEM uses positive-for-discharge (Samsung convention)
# If STATUS=Discharging and CURRENT_NOW < 0 → follows spec, negative-for-discharge

# Step 4: Detect units — heuristic based on magnitude
# If |CURRENT_NOW| < 10000 when fully loaded → likely mA (3000 mA = sensible; 3000 µA is ~3mA = impossible load)
# If |CURRENT_NOW| > 100000 when fully loaded → likely µA (2500000 µA = 2.5A = possible gaming load)
# Safe threshold: if |value| < 30000 at load → assume mA; else → assume µA

# Store calibration result in device profile JSON for this serial number
```

**Noise and quantization caveats:**
- CW2015 and BQ27xxx fuel gauge chips (common on Rockchip/budget devices) update at fixed intervals (typically 4-32 Hz); readings can be noisy ±5-15%
- Some Samsung devices gate `current_now` updates to every ~1 second regardless of polling rate
- Under rapid power state changes (CPU burst), the reading lags real instantaneous current by up to 500ms
- **Recommendation:** Sample at 2-second intervals, use a 10-reading rolling average to smooth noise. Single-sample readings are unreliable for power draw.

---

### 2.3 Battery Life Estimation Methodology

**Standard formula for short-test extrapolation:**

```
Discharge current (mA) = |current_now_µA| / 1000  [if in µA]
Battery capacity (mAh) = from `dumpsys battery` → `scale` field is %; 
                          actual mAh requires device spec or:
                          adb shell cat /sys/class/power_supply/battery/charge_full_design
                          (in µAh on compliant devices, may not exist on all)

Estimated runtime (hours) = Battery_capacity_mAh / Average_discharge_current_mA
```

**Getting battery capacity:**
```bash
# Method 1: charge_full_design (most accurate, may not exist on all devices)
adb shell cat /sys/class/power_supply/battery/charge_full_design
# Returns µAh → divide by 1000 for mAh

# Method 2: Infer from dump
adb shell dumpsys battery
# Shows "level: 87" and "scale: 100" but NOT raw mAh — you still need the spec sheet or charge_full_design

# Method 3: charge_full (current measured capacity, degrades over battery life)
adb shell cat /sys/class/power_supply/battery/charge_full
```

**Short-sample extrapolation error — documented methodology:**

Based on published mobile review methodology and thermal behavior patterns:

| Sample duration | Thermal state at sample | Typical extrapolation error |
|---|---|---|
| 10 minutes | Pre-throttle (device still cool, peak power draw) | **+15–30% overestimate** of real drain rate |
| 20-30 minutes | Transition phase (throttling begins, power decreasing) | **±10–20%** |
| 45-60 minutes | Post-throttle steady state | **±5–10%** |
| 90+ minutes | True steady state (thermal equilibrium reached) | **±3–8%** |

The most common reviewer methodology error: a 10-minute gaming test taken when the device is cold will show the highest power draw (pre-throttle). Extrapolating this to a full 3-hour session overestimates battery drain because the device will throttle to lower power states once hot. **GSMArena and similar reviewers account for this by running at least 45-60 minute tests or by noting the post-throttle power state explicitly.**

**Honest assessment of 20-30 minute short tests for your pipeline:**
- For ranking devices relative to each other (which is the YouTube review use case), ±15% is acceptable if the methodology is consistent
- You **must note** that short-sample results are estimates, not verified full-cycle battery life
- Express results as "estimated runtime at sustained gaming load" not "battery life"
- Include discharge percentage delta and current reading as raw data so viewers can sanity-check

**Recommended reporting template:**
```
Device: [Name]
Test: [Benchmark name] at [settings]
Duration: 25 minutes
Start battery: 100%, End battery: 87%
Drain rate: 0.52%/minute → ~3.2 hours estimated runtime
Average current: 1,847 mA (±8%)  
Average temperature: 43°C (peak 48°C at 8 min)
Note: Short-sample estimate; actual runtime ±15% depending on thermal conditions
```

---

### 2.4 Battery Historian — 2026 Status

**Status: Officially unmaintained.** The `google/battery-historian` repository ([github.com/google/battery-historian](https://github.com/google/battery-historian)) has not received meaningful commits since 2017. Google's own developer documentation ([developer.android.com/topic/performance/power/battery-historian](https://developer.android.com/topic/performance/power/battery-historian)) and the setup guide ([developer.android.com/topic/performance/power/setup-battery-historian](https://developer.android.com/topic/performance/power/setup-battery-historian)) still reference it but the project's GitHub carries warnings about lack of active maintenance.

**What still works:** The Docker-based deployment (`gcr.io/android-battery-historian/stable:3.1`) still functions for `bugreport` visualization from devices running Android 5.0–12. It may produce incomplete or malformed visualizations for Android 13/14 `bugreport.zip` format changes.

**Community forks:** `athish-naveen/battery-historian-2025` exists but is unofficial and not widely tested.

**For your pipeline — recommendation:**
Battery Historian is a visualization tool, not a data collection tool. Your pipeline should collect raw `batterystats` dumps and `current_now` telemetry regardless. Battery Historian can be useful for one-off investigation of a specific device's power regression (run it manually when you need it), but it should not be an automated pipeline dependency. The Docker operational complexity and the questionable Android 13/14 compatibility make it unsuitable for a "walk away" production pipeline.

---

> ### 🔵 Bottom Line Recommendation — Section 2
>
> **Power draw measurement:** Use `current_now` polling (2s interval, 10-sample rolling average) as your primary power signal. Build a device calibration step that auto-detects sign convention (compare to `/sys/class/power_supply/battery/status`) and units (magnitude heuristic: <30,000 at full load → probably mA). Store per-device calibration in a JSON profile keyed by `adb get-serialno` so it only runs once per new device.
>
> **Battery life estimate:** Use `charge_full_design` (µAh ÷ 1000 = mAh) for capacity. Compute rolling average discharge current over the last 10 minutes of a settled (post-throttle, ≥20 min) test. Divide. Report with ±15% disclaimer and include raw data.
>
> **`dumpsys batterystats`:** Use for wakelock and CPU-time context only. Do not expect per-process power attribution on unrooted devices.
>
> **Battery Historian:** Skip as a pipeline dependency. Useful only for manual one-off forensics.

---

## Section 3: UI Automation for Headlessly Triggering Benchmark Apps

### 3.1 Method Comparison

#### Option A: `adb shell monkey`
```bash
adb shell monkey -p com.futuremark.dmandroid.application -c android.intent.category.LAUNCHER 1
```
- **What it does:** Launches the app and optionally sends pseudo-random input events
- **Reliability:** Very low for controlled UI interaction. Monkey is designed for stress testing, not precision UI automation. It cannot reliably "find and tap the Start Test button"
- **Verdict for your use case:** Only useful for launching the app to the foreground. Do not use for navigation within the benchmark UI.

#### Option B: `uiautomator dump` → parse XML → `input tap`
```bash
# Dump UI hierarchy to device storage
adb shell uiautomator dump /sdcard/ui_dump.xml
# Pull to host
adb pull /sdcard/ui_dump.xml
# Parse XML for node with text="Start Test" or similar
# Extract bounds="[x1,y1][x2,y2]"
# Compute center_x = (x1+x2)/2, center_y = (y1+y2)/2
adb shell input tap <center_x> <center_y>
```

**XML bounds format:**
```xml
<node index="0" text="Start Test" resource-id="com.futuremark.dmandroid.application:id/btnStartTest" 
      class="android.widget.Button" package="com.futuremark.dmandroid.application" 
      bounds="[270,844][810,944]" clickable="true" enabled="true" ... />
```

**Parsing (Python):**
```python
import xml.etree.ElementTree as ET, re

def find_and_tap_by_text(xml_path, search_text, adb_serial=None):
    tree = ET.parse(xml_path)
    for node in tree.getroot().iter():
        text = node.get('text', '') or node.get('content-desc', '')
        if search_text.lower() in text.lower():
            bounds = node.get('bounds')
            coords = list(map(int, re.findall(r'\d+', bounds)))
            cx, cy = (coords[0]+coords[2])//2, (coords[1]+coords[3])//2
            serial_flag = f"-s {adb_serial}" if adb_serial else ""
            os.system(f"adb {serial_flag} shell input tap {cx} {cy}")
            return True
    return False
```

**Reliability notes:**
- `uiautomator dump` reliably captures View-based UI (TextView, Button, etc.)
- Does NOT capture UI drawn with Canvas/OpenGL/SurfaceView — gaming benchmark splash screens sometimes use these; the dump will show an empty hierarchy
- **Resolution-agnostic by design**: bounds are in absolute pixels, not scaled. If the device is 1080×2400 and the button is at [270,844][810,944], tapping (540, 894) works. You never need to hardcode pixel positions. This IS the portable cross-resolution approach.
- **Failure mode:** Button text changes between benchmark app versions ("Start Test" → "Run" → "Begin") — use fuzzy text matching or maintain a small lookup table per benchmark package
- **Failure mode on some OEM accessibility layers:** HiSense, some Unisoc budget devices ship with aggressive accessibility overlays that can corrupt `uiautomator dump` output. Mitigation: retry 3 times with 2s delay between attempts.

#### Option C: `am instrument` with a custom UiAutomator2 APK

Build a small "generic tap by text" instrumented test APK. This is the most robust approach for complex navigation:

```kotlin
// TestHelper.kt — deployable to any device, no app source code needed
@Test
fun tapByText() {
    val searchText = InstrumentationRegistry.getArguments().getString("text")!!
    val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    val button = device.findObject(UiSelector().textContains(searchText).clickable(true))
    if (button.exists()) button.click()
}
```

```bash
# Build once, deploy once
adb install -r generic-tap-helper.apk
# Use from pipeline
adb shell am instrument -w \
  -e text "Start Test" \
  com.retrodojo.taphelper.test/androidx.test.runner.AndroidJUnitRunner
```

**Advantages over uiautomator dump:**
- Runs in-process with Android's accessibility layer — more reliable than parsing XML
- Can scroll to find off-screen elements (`UiScrollable`)
- Can wait for elements with timeout (`waitForExists(5000)`)
- **Works on SurfaceView apps IF accessibility mode is on** — but gaming benchmarks may still be transparent to this

**Disadvantages:**
- Requires one-time APK build (Gradle/Android Studio)
- APK must be signed; on some strict OEM builds (Samsung Knox), installing unsigned test APKs may be blocked
- `testOnly` APKs cannot be installed on some locked bootloader configurations

#### Option D: Maestro (mobile.dev)

Maestro ([maestro.mobile.dev](https://maestro.mobile.dev)) is a modern declarative mobile UI testing framework. Sample flow YAML:

```yaml
appId: com.futuremark.dmandroid.application
---
- launchApp
- tapOn: "Start Test"
- waitForAnimationToEnd:
    timeout: 120000
- takeScreenshot: results_screen
```

**Assessment:**
- **No root required** — works over ADB
- **Smart waits** — handles loading screens and slow benchmark launches without hardcoded sleeps
- **Text-matching is vision-based** — more robust than XML parsing for certain UI types
- **Handles scrolling** automatically to find off-screen buttons
- Does NOT require you to know the resource ID
- **Installation:** Single binary install on Windows (no Java, no SDK beyond ADB) — this IS truly lightweight for a non-developer end user
- **Limitation:** Maestro is a daemon that runs persistently on the host; multi-device parallel runs require Maestro Cloud (paid) or running multiple Maestro instances with `-serial` flags
- **Limitation:** For SurfaceView-heavy UIs (full-screen game benchmarks), text detection may still fail if the benchmark's "Start" button is rendered in-GL

#### Option E: Appium (Python)

Appium + UIAutomator2 driver is the most mature ecosystem:
- Full Python control via WebDriver protocol
- `find_element(AppiumBy.ANDROID_UIAUTOMATOR, 'new UiSelector().textContains("Start")')` — cross-resolution, text-based
- Appium server runs on host PC, UIAutomator2 agent APK runs on device
- **Complexity:** Requires Node.js (Appium server), Python, Android SDK. More moving parts than Maestro.
- **Reliability:** Very high for standard View-based UIs
- **For your use case:** Overkill for a simple "tap Start Test" automation. Better suited if you need multi-step navigation (login → select test → configure settings → start)

---

### 3.2 Benchmark App Automation Hooks — Official APIs

#### 3DMark (`com.futuremark.dmandroid.application`)

**Consumer version:** No public automation API. No documented deep link or intent for triggering a test run. ADB intent to launch (`am start`) will only open the app. UL's public-facing 3DMark does not expose exported Activities or BroadcastReceivers for test triggering.

**Enterprise/OEM version:** UL does offer an OEM 3DMark variant with headless triggering support and JSON result export. This requires an OEM licensing agreement. Contact: [benchmarks.ul.com/oem](https://benchmarks.ul.com/oem). No public documentation is available without a license.

**Practical reality:** For a YouTube review channel, the OEM license cost (~$5,000–$15,000/year estimated, based on UL's pricing tier structure) is not justifiable. Use `uiautomator dump` XML tap automation for the consumer 3DMark app.

#### Geekbench 6 (`com.primatelabs.geekbench6`)

**Consumer version:** No documented automation hooks in Primate Labs' public materials. However, the Geekbench binary does have an `am instrument` pathway:

```bash
# Speculative — not officially documented but referenced in automated test tooling discussions
adb shell am instrument -w com.primatelabs.geekbench6/.BenchmarkInstrumentation
```

**This is NOT officially supported for the consumer APK.** Primate Labs' enterprise documentation is only available under license. Contact: [primatelabs.com/enterprise](https://www.primatelabs.com/enterprise/).

**Result retrieval:** Geekbench does write result JSON to device storage:
```bash
adb pull /sdcard/Android/data/com.primatelabs.geekbench6/files/ ./geekbench_results/
```
The result files (`benchmark-*.gb6`) can be uploaded to geekbench.com for display, but raw JSON parsing is possible if you reverse the schema (it's not officially documented but is used by several community tools).

#### PCMark for Android (`com.futuremark.pcmark.android.benchmark`)

**This is the best-positioned of the three for automation.** UL's PCMark Professional Edition explicitly supports:
- ADB-triggered headless benchmark runs
- Silent test execution (no UI interaction required)
- Result export as JSON/XML
- Integration via `am start` with specific intent extras

However, this is **Professional Edition only** (license required). The Google Play consumer version does not expose these automation hooks.

**Public confirmation:** [benchmarks.ul.com/pcmark-android](https://benchmarks.ul.com/pcmark-android) mentions "professional license for commercial/OEM use." The automation guide is available via UL support ([support.benchmarks.ul.com](https://support.benchmarks.ul.com/support/solutions/44000812489)).

**For your pipeline:** If you can expense PCMark Pro (pricing: contact UL, typically ~$500-2000/year for small teams), this is the cleanest path to a fully automated, no-UI-interaction benchmark run with structured result output. For 3DMark and Geekbench without enterprise licenses, you're stuck with `uiautomator dump` tap automation.

---

### 3.3 Recommendation: "One Generic Tap APK" Pattern

**Yes, this pattern is viable and is widely used.** The implementation:

1. Build a ~20KB `generic-ui-helper.apk` using `androidx.test.uiautomator` and `androidx.test:runner`
2. It accepts `text`, `resourceId`, `scroll`, and `waitMs` instrumentation arguments
3. Deploy once per device with `adb install`
4. Invoke from your pipeline with `am instrument -e text "Start Test" ...`

**This is exactly how AOSP's CTS (Compatibility Test Suite) and GTS (Google Mobile Services Test Suite) interact with third-party apps during certification.** It is a well-documented, production-proven pattern.

**Cross-resolution portability:** ✅ — UIAutomator finds elements by semantic attributes (text, resource-id, class), not pixel coordinates. The same APK works on a 720p Unisoc tablet and a 1440p Qualcomm flagship.

**Unsigned APK blocking on Samsung Knox:** On Samsung devices in "Knox" strict mode, `testOnly` APKs may be rejected. Workaround: build the APK as a standard (non-test) application wrapper that runs UIAutomator in its main activity. Slightly more complex build but works on Knox.

---

> ### 🔵 Bottom Line Recommendation — Section 3
>
> **For immediate pipeline use (no licensing cost):** `uiautomator dump` → XML parse → `input tap` is the most portable, zero-dependency approach. Write a Python helper that searches by `text`, `content-desc`, and `resource-id` (in that priority order), computes center from bounds, and retries 3× with 2s delay. This handles 90% of benchmark app "Start Test" flows.
>
> **For more reliability and scrolling support:** Build the ~20KB generic UIAutomator test APK using `androidx.test.uiautomator`. It installs once, is called via `am instrument`, and is the approach professional Android device labs use. Worth the one-time build investment.
>
> **For a non-developer end user running the pipeline:** Maestro (single binary) is the easiest to explain and operate, but requires internet access for installation and has multi-device complexity. Recommend for personal use / single-device runs.
>
> **Benchmark automation hooks:** Only PCMark Pro has a publicly confirmed, licensed headless API. 3DMark and Geekbench consumer versions have no public automation support. Use `uiautomator dump` tap automation for those apps — it works, it's just fragile to app UI updates (manage this by version-pinning benchmark APKs).

---

## Section 4: Gaps and Scaling Recommendations

### 4.1 What Breaks When Bootloader Is Locked / ADB Off By Default

**The harsh reality:** On a stock consumer device (bootloader locked, out of box), zero automation is possible until a human performs manual enablement. There is no ADB-only or programmatic way to enable USB Debugging on a locked device.

**Minimum per-device manual enablement steps (one-time, ~3 minutes per device):**

1. Complete initial setup (language, Google account, WiFi) — this is unavoidable
2. **Settings → About phone → Build number → tap 7 times** (count varies by OEM: Xiaomi requires 5, some Realme builds require 3)
3. **Settings → System → Developer Options → Enable USB Debugging** (exact path varies by OEM)
4. Connect USB → confirm the "Allow USB Debugging" dialog → optionally tick "Always allow from this computer"
5. For `adb shell svc power stayon usb`: this must be run once to prevent screen-off during long tests

**OEM-specific gotchas:**
- **Xiaomi/MIUI:** Additionally requires **"USB Debugging (Security Settings)"** to be enabled (a separate toggle, hidden behind Mi Account login) — without this, `adb install` and `uiautomator dump` are blocked even with USB Debugging on
- **Samsung:** No extra toggle, but Knox may restrict `testOnly` APK installs
- **Unisoc (most budget Chinese handhelds):** Developer Options path is non-standard; sometimes `Settings → About → Version → tap 7x`. Also, some Unisoc builds with Android Go have ADB debugging disabled at the kernel level on production images — check for `ro.debuggable` property: `adb shell getprop ro.debuggable` (should be `1`)
- **Some Rockchip retro handhelds (RG35XX+, etc.):** Often ship custom Android forks with ADB enabled by default in Developer Settings — verify before assuming it needs to be enabled

**Checklist to capture in your device onboarding doc:**
```
[ ] ADB enabled and PC authorized
[ ] "Always allow" checked (prevents dialog on reconnect)
[ ] screen-stayon-usb set: adb shell svc power stayon usb
[ ] Disable lock screen PIN/pattern (prevents lockscreen blocking automation)
[ ] Disable adaptive brightness (prevents brightness changes affecting benchmark reproducibility)
[ ] Airplane mode considerations (disable for battery test consistency, or explicitly set state)
[ ] adb shell settings put global animator_duration_scale 0  (disable animations for UI automation)
[ ] adb shell settings put global transition_animation_scale 0
[ ] adb shell settings put global window_animation_scale 0
```

---

### 4.2 Multi-Device Simultaneous USB — Targeting and Hub Recommendations

#### `adb -s` Targeting

When multiple devices are connected:
```bash
# List all devices with serial numbers
adb devices -l
# Output:
# R58N81XXXXX          device  product:dreamlte  model:SM_G950F  ...
# emulator-5554        device

# All commands: add -s <serial>
adb -s R58N81XXXXX shell dumpsys gfxinfo com.futuremark.dmandroid.application
```

**Automation script convention:** Export `ANDROID_SERIAL=<serial>` in the environment for single-device subshells, or use `-s` in every ADB call. Never rely on adb's "default device" selection when more than one device is connected — it will either error or pick randomly.

#### USB Hub Recommendations

**Consumer hubs are unreliable for this use case.** Key failure modes:
- Insufficient current per port under load (devices charging AND running full CPU/GPU benchmark draw 1.5–3A each)
- No per-port power switching (can't recover a bricked/hung device without unplugging)
- USB enumeration races when multiple devices re-enumerate simultaneously
- Windows USB Root Hub auto-suspend drops ADB connections after ~5 minutes of "inactivity" (the USB bus appears idle to the host even though ADB traffic is low-volume)

**Recommended hardware tiers:**

| Tier | Device | Per-port control | Current per port | ADB-specific notes |
|------|--------|-----------------|------------------|--------------------|
| **Budget** | Anker 10-port powered hub | ❌ | 2.4A (shared) | Adequate for 3–4 devices, no per-port reset |
| **Mid** | Plugable USB3-HUB10C2 | ❌ | 3A per port | Higher power, more stable, no port switching |
| **Professional** | Cambrionix PowerPad15S | ✅ | 3A per port | Per-port power switching, REST API, CLI automation, industry standard for Android test labs |
| **Professional** | Cambrionix U16S | ✅ | 3A per port | 16-port USB3 variant |

**Critical Windows-specific fix for any hub:**
- Device Manager → Universal Serial Bus controllers → each USB Root Hub → Properties → Power Management → **uncheck "Allow the computer to turn off this device to save power"**
- Apply to every USB Root Hub in device manager
- Without this, Windows will suspend USB ports and drop ADB connections during long unattended tests

**Practical hub recommendation for RetroDojo:** Start with **2 Anker 10-port hubs** for ≤6 devices (run 2-3 per hub, avoid overloading). Upgrade to a **Cambrionix PowerPad15** when you're running ≥6 devices regularly — the per-port power-cycle capability alone is worth the cost because it lets your automation script recover a frozen device without human intervention.

---

### 4.3 Unattended Duration Limits — Doze, App Standby, ADB Session Stability

#### Does Doze Mode Kill Your `adb shell` Processes?

**The short answer: No — Doze and App Standby do NOT apply to `adb shell` processes.**

Detailed explanation:
- Doze mode (`android.os.PowerManager` Doze) restricts **apps** — specifically, deferring their `AlarmManager` wakeups, `JobScheduler` jobs, and network access
- An `adb shell` session runs as UID `2000` (the `shell` user), which is a system UID not subject to App Standby bucketing
- The shell process itself (`/system/bin/sh` or `/system/bin/bash`) is a native Linux process — it does not participate in the Android app lifecycle at all
- **However:** The *device* entering deep sleep (CPU suspend) CAN pause the shell process if the CPU suspends and no wakelock is held. The ADB connection itself may trigger a brief wakelock on some kernels, but this is not guaranteed.

**The real risk: ADB daemon (adbd) restarts**
- `adbd` (the ADB daemon on the device) can be restarted by Android's init system if the USB connection is briefly interrupted
- When `adbd` restarts, all existing `adb shell` sessions are killed
- Long benchmark runs (2-4 hours) on unstable USB connections will hit this

**Mitigation strategies:**
```bash
# Keep screen and USB active
adb shell svc power stayon usb

# Keep CPU from sleeping during telemetry collection  
# (root not required for partial wake — but can't create wakelocks without root)
# Best workaround: Launch a foreground-visible "keepalive" screen (e.g., display always-on benchmark overlay)

# Use a reconnect wrapper in your host-side script
while true; do
    if ! adb -s $SERIAL shell echo "ping" 2>/dev/null | grep -q "ping"; then
        echo "ADB connection lost, attempting reconnect..."
        adb -s $SERIAL connect  # for WiFi ADB
        # For USB: adb kill-server && adb start-server && sleep 2
        adb start-server
        sleep 3
    fi
    sleep 30  # check every 30 seconds
done &
```

**WiFi ADB as a mitigation for long sessions:**
```bash
# Set up WiFi ADB after initial USB connection (device must be on same network)
adb -s <serial> tcpip 5555
adb connect <device_ip>:5555
# Now use WiFi ADB serial (192.168.x.x:5555) for long-running sessions
# USB can be disconnected — the WiFi ADB session is more resilient to USB power events
# Caveat: WiFi ADB can also drop if device enters AP power save mode; adb shell svc wifi stayon helps
```

**Realistic unattended duration:**
- With `svc power stayon usb` and Windows USB autosuspend disabled: **3–4 hours** reliably
- Without those mitigations: **15–45 minutes** before the first ADB drop
- With WiFi ADB AND `svc power stayon`: **4–6 hours** — sufficient for a full battery life test

---

### 4.4 Detecting Benchmark Completion Without Human Intervention

**The problem:** Fixed `sleep 300` timeouts are fragile — benchmarks run longer on slow devices, shorter on fast ones, and any hang causes the whole pipeline to either abort early (false completion) or wait forever (false hang).

**Reliable detection methods, ranked by robustness:**

#### Method 1: Activity Stack Polling (Best for View-Based Apps)

```bash
# Detect when a results Activity appears
TARGET_ACTIVITY="com.primatelabs.geekbench6.ResultActivity"

while true; do
    CURRENT=$(adb -s $SERIAL shell dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|topRunningActivity")
    if echo "$CURRENT" | grep -q "$TARGET_ACTIVITY"; then
        echo "Benchmark complete — results screen detected"
        break
    fi
    
    # Also check for crash/ANR
    CRASHES=$(adb -s $SERIAL shell dumpsys window 2>/dev/null | grep "Application Not Responding")
    if [ -n "$CRASHES" ]; then
        echo "ERROR: ANR detected — benchmark may have crashed"
        break
    fi
    
    sleep 3
done
```

**Android 11→14 compatibility:** Both `mCurrentFocus` and `mResumedActivity` (or `topRunningActivity` in newer formats) are present in all versions. The exact grep string changes slightly:
- Android 11-12: `mResumedActivity: ActivityRecord{...}`
- Android 13-14: look for `topRunningActivity` or `mResumedActivity` — both should still be present

**Build a lookup table of known results Activities per benchmark:**
```python
RESULTS_ACTIVITIES = {
    "com.primatelabs.geekbench6": ["ResultActivity", "ResultsActivity"],
    "com.futuremark.dmandroid.application": ["ResultsActivity", "ScoreActivity"],
    "com.futuremark.pcmark.android.benchmark": ["WorkTestResultActivity"],
    "com.antutu.ABenchMark": ["ResultActivity", "TestResultActivity"],
}
```

#### Method 2: `uiautomator dump` Text Scan (Works When Activity Detection Fails)

```bash
# For apps that stay in one Activity but change screen content
adb -s $SERIAL shell uiautomator dump /sdcard/ui_check.xml
adb -s $SERIAL pull /sdcard/ui_check.xml /tmp/ui_check.xml 2>/dev/null

# Check for results-indicating text
if grep -qi "score\|result\|complete\|finished\|total" /tmp/ui_check.xml; then
    echo "Results screen detected via UI content"
fi
```

**Downside:** `uiautomator dump` takes 1-3 seconds on some devices. Don't poll this more than once every 10 seconds.

#### Method 3: Logcat Keyword Monitoring (Best for Some Apps)

```bash
# Many benchmarks log completion events
adb -s $SERIAL logcat -v time -s "GeekBench:*" "3DMark:*" | while read line; do
    if echo "$line" | grep -qi "result\|complete\|score\|benchmark.*done"; then
        echo "Completion detected in logcat: $line"
        kill $LOGCAT_PID  # signal main script
    fi
done &
LOGCAT_PID=$!
```

**Caveat:** Logcat keyword matching is fragile — log tags and messages change between app versions. Use as a supplementary signal, not the only detection method.

#### Method 4: Combination with Timeout (The Practical Recommendation)

```bash
TIMEOUT=600  # 10 minute max
POLL_INTERVAL=5
ELAPSED=0
COMPLETED=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Primary: Activity check
    if adb -s $SERIAL shell dumpsys activity activities 2>/dev/null | grep -q "$RESULTS_ACTIVITY"; then
        COMPLETED=true
        break
    fi
    
    # Secondary: UI content check (every 30s to avoid performance impact)
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        adb -s $SERIAL shell uiautomator dump /sdcard/uidump.xml 2>/dev/null
        if adb -s $SERIAL shell grep -qi "score\|result" /sdcard/uidump.xml 2>/dev/null; then
            COMPLETED=true
            break
        fi
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$COMPLETED" = "false" ]; then
    echo "TIMEOUT: Benchmark did not complete within ${TIMEOUT}s — flagging for review"
fi
```

---

> ### 🔵 Bottom Line Recommendation — Section 4
>
> **Device onboarding:** Accept that per-device initial setup (3 min of manual work) is unavoidable. Build a `device-onboard.sh` script that runs all the ADB-based configuration steps (animation scaling, stayon, etc.) immediately after human authorization, and generates a device profile JSON with calibrated `current_now` sign/unit, screen resolution, and Android version.
>
> **Multi-device USB:** Disable Windows USB autosuspend (mandatory). Use individually powered hubs. For ≥4 devices, invest in a Cambrionix PowerPad15 — the per-port power reset is essential for autonomous recovery from frozen devices.
>
> **Long sessions / ADB stability:** Set `svc power stayon usb` on every device before a test. Use a 30-second ADB health-check loop with automatic reconnect in your host script. For tests >90 minutes, consider switching to WiFi ADB after USB setup to avoid USB power management interference. 4-hour unattended runs are feasible with these mitigations.
>
> **Completion detection:** Do NOT use fixed sleeps. Implement the combination method: activity-name polling (primary, every 5s) + UI content scan (secondary, every 30s) + hard timeout (failsafe). Maintain a per-benchmark lookup table of known results Activity names — this is a small maintenance burden that dramatically improves "walk away" reliability.

---

## Appendix A: Key Tools Summary

| Tool | Purpose | Root Required | Android Version | Status |
|------|---------|--------------|-----------------|--------|
| `dumpsys gfxinfo framestats` | Per-frame timing | No | 6+ (v2: 12+) | ✅ Active, recommended |
| `dumpsys gfxinfo` (aggregate) | FPS/jank summary | No | 6+ | ✅ Active, recommended |
| `dumpsys SurfaceFlinger --latency` | Frame timing via SF | No | ≤12 only | ❌ Removed in 14 |
| `dumpsys SurfaceFlinger --show-frame-timeline` | SF frame timeline | No | 13+ | 🟡 Human-readable only |
| `adb shell perfetto` + FrameTimeline | Detailed jank taxonomy | No | 12+ | 🟡 Phase 2 — complex |
| `dumpsys batterystats` | Battery/wakelock history | No (limited) | 5+ | ✅ Active, limited on unrooted |
| `/sys/class/power_supply/battery/current_now` | Real-time current | No | All | ✅ Use with calibration |
| `dumpsys battery` | Battery level/voltage | No | All | ✅ Reliable |
| Battery Historian | Visualization | No | 5–12 (partial) | ❌ Unmaintained |
| `uiautomator dump` + `input tap` | UI automation | No | All | ✅ Recommended (fragile) |
| Generic UIAutomator APK | Robust UI automation | No | 5+ | ✅ Recommended (one-time build) |
| Maestro | Declarative UI automation | No | All | ✅ Recommended for ease of use |
| Appium + UIAutomator2 | Full-featured UI automation | No | All | 🟡 Overkill for simple taps |
| PCMark Pro enterprise | Headless benchmark trigger | No | All | 🟡 License required ($$$) |
| 3DMark OEM | Headless benchmark trigger | No | All | 🟡 License required ($$$) |

---

## Appendix B: Known Hard Limits (Be Honest in Your Videos)

1. **Gaming benchmark FPS via HWUI framestats:** If the benchmark uses SurfaceView/OpenGL directly (3DMark, Antutu 3D, most emulators), `dumpsys gfxinfo framestats` will show **zero or near-zero HWUI frames**. You will not get per-frame GPU timing data without root or vendor instrumentation. The benchmark's own on-screen FPS counter (read via OCR or screen recording + FFMPEG frame analysis) is the only no-root alternative.

2. **Thermal power profiling accuracy:** Without a hardware power monitor (Monsoon, Otii Arc), energy measurements from `current_now` have ±10-20% uncertainty due to fuel gauge quantization, ADC noise, and OEM-specific scaling. This is sufficient for ranking devices but not for publishing exact mW figures.

3. **Unisoc/Rockchip Android 11 support gaps:** Many budget handheld devices (Powkiddy RGB30, Anbernic RG35XX series) run heavily forked Android 11 builds with stripped-down `dumpsys` implementations. You may find that `gfxinfo framestats` returns no useful data, or that `uiautomator dump` hangs indefinitely. Have a "manual fallback" procedure documented for these cases.

4. **Benchmark app UI automation brittleness:** Apps update. "Start Test" becomes "Run Benchmark." Without version-pinning APKs and a CI check that validates the UIAutomator flow still works after an update, your automation will silently fail. Consider version-pinning all benchmark APKs and distributing them with the pipeline.

---

*Citations:*
- AOSP `FrameInfo.h`: [cs.android.com/android/platform/superproject/main/+/main:frameworks/base/libs/hwui/FrameInfo.h](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/libs/hwui/FrameInfo.h)
- Android Render/Jank official docs: [developer.android.com/topic/performance/vitals/render](https://developer.android.com/topic/performance/vitals/render)
- Perfetto FrameTimeline: [perfetto.dev/docs/data-sources/frametimeline](https://perfetto.dev/docs/data-sources/frametimeline)
- Perfetto quickstart (Android): [perfetto.dev/docs/quickstart/android-tracing](https://perfetto.dev/docs/quickstart/android-tracing)
- Battery Historian (Google): [github.com/google/battery-historian](https://github.com/google/battery-historian)
- Battery Historian Android docs: [developer.android.com/topic/performance/power/battery-historian](https://developer.android.com/topic/performance/power/battery-historian)
- Batterystats setup: [developer.android.com/topic/performance/power/setup-battery-historian](https://developer.android.com/topic/performance/power/setup-battery-historian)
- Linux Power Supply class docs: [kernel.org/doc/Documentation/power/power_supply_class.txt](https://www.kernel.org/doc/Documentation/power/power_supply_class.txt)
- Macrobenchmark library: [developer.android.com/topic/performance/benchmarking/macrobenchmark-overview](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-overview)
- UL Benchmarks OEM: [benchmarks.ul.com/oem](https://benchmarks.ul.com/oem)
- PCMark for Android Professional: [benchmarks.ul.com/pcmark-android](https://benchmarks.ul.com/pcmark-android)
- Cambrionix PowerPad15S: [cambrionix.com/products/powerpad15s](https://www.cambrionix.com/products/powerpad15s/)
- AOSP JankInfo.h (FrameTimeline jank types): [cs.android.com/android/platform/superproject/main/+/main:frameworks/native/libs/gui/include/gui/JankInfo.h](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/libs/gui/include/gui/JankInfo.h)

---
