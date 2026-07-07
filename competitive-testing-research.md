# RetroDojo Competitive Testing Gap Report

## Executive summary

Retro-handheld reviews today are useful but rarely lab-grade. Most niche reviewers combine subjective ergonomics/control impressions, emulator compatibility checks, gameplay footage, and occasional synthetic benchmarks. A few outlets publish numbers — Geekbench, AnTuTu, 3DMark, battery estimates, temperatures — but the method is usually not automated, not repeated across a growing public dataset, and not tied to frame pacing/input latency in emulation.

The defensible gap for RetroDojo is not "running benchmarks"; many people already do that. The gap is a repeatable handheld-specific test bench: standardized Android/Linux telemetry, sustained-performance tests, emulator frame pacing, battery drain by workload class, WiFi/storage/controller measurements, and one cheap physical latency/FPS rig. This would sit between enthusiast YouTube reviews and NotebookCheck/Digital Foundry-style rigor.

---

# 1. What major reviewers/outlets do today

## RetroGameCorps

RetroGameCorps is strong on buyer guidance, setup, firmware, emulator recommendations, and qualitative usability. In the RG556/RG Cube guide, Russ notes that both devices use the Unisoc T820 and "can play up to GameCube and PS2 with most games playing at upscaled resolutions," but this is presented as practical compatibility guidance, not a published telemetry methodology. He also documents practical device behavior: "High Mode" does not seem to add performance benefit, fan controls exist, and the device "doesn't ever really get that hot" in typical use. Source: RetroGameCorps RG556/RG Cube setup guide, https://retrogamecorps.com/2024/02/24/anbernic-rg556-setup-guide/

**Assessment:** excellent qualitative and setup authority; limited public raw benchmark methodology. No evidence of scripted battery rundown, raw frame-time logs, thermal-camera workflow, or published telemetry datasets.

## ETA Prime

ETA Prime commonly shows synthetic benchmarks, gameplay tests, and emulator/native-game demonstrations for handhelds and mini PCs. The format is performance-oriented but generally video-centric: viewers see scores and gameplay, not a repeatable public methodology or raw logs.

**Assessment:** useful benchmark/gameplay demonstrations; little evidence of public raw data, scripted repeatability, or emulation frame-time methodology.

## Retro Handhelds

Retro Handhelds has become one of the more quantitative niche outlets. In its AYN Odin 3 review, the author reports 3DMark Wild Life Extreme stress-test results: high loop score 6541 and 97.9% stability, then compares that to Odin 2, Retroid Pocket G2, AYANEO/Konkr, and RG477M stability ranges. Source: Retro Handhelds AYN Odin 3 review, https://retrohandhelds.gg/ayn-odin-3-review/

**Assessment:** uses meaningful synthetic stress testing and cross-device comparisons. Still, the article's emulation section is mostly "what ran well" rather than logged frame pacing, input latency, battery drain curves, or raw telemetry.

## DroiX

DroiX is more explicitly quantitative than many handheld reviewers. In its Retroid Pocket 5 review, DroiX describes a high-performance battery test: AnTuTu loop, processor high-performance mode, ~4h15m runtime. It also measures fan noise — average 58 dB on Sport fan mode, 62 dB with custom fan settings — and maximum temperature around 42°C. It runs Geekbench 5/6, AnTuTu, and 3DMark. Source: DroiX Retroid Pocket 5 review, https://droix.net/blogs/retroid-pocket-5-review/

**Assessment:** good benchmark coverage, some battery/thermal/noise numbers. But it is still not a full telemetry pipeline with per-minute CPU/GPU clocks, throttling curves, raw CSVs, frame-time plots, or input-lag testing.

## Digital Foundry

Digital Foundry is the gold standard for frame pacing and latency analysis. Their FromSoftware frame-pacing article explains that 30fps is not enough if frames arrive inconsistently; ideal 30fps means one frame every 33.3ms, while bad pacing can deliver frames at 16.7ms, 33.3ms, or 50ms intervals, producing visible stutter. Source: Digital Foundry, "From Software's notorious 30fps stutter fixed," https://www.digitalfoundry.net/articles/digitalfoundry-2022-from-software-30fps-frame-pacing-fixed-by-hackers

Digital Foundry also uses high-speed-camera input-lag comparisons: "high speed cameras can be used to compare input lag," synchronizing camera feeds to a button press and averaging results across samples. Same source.

Older DF latency methodology also cites Mick West's camera technique: film the controller and display together, count frames between button press and screen response, and convert frames to milliseconds. Source: Digital Foundry "Console Gaming: The Lag Factor," https://www.digitalfoundry.net/articles/digitalfoundry-lag-factor-article

**Assessment:** extremely rigorous for games/consoles, but not focused on cheap Android/Linux retro handhelds or emulator/device setup workflows.

## GSMArena

GSMArena's phone battery methodology is highly standardized. Its Battery Test 2.0 measures discharge from 100% to 0% across four active-use scenarios: calls, web browsing, video streaming, and gaming. It fixes screen brightness at 200 nits, enables location, uses airplane mode with WiFi active for screen-on tests, sets volume to 15%, and automates tests with SmartViser. Source: GSMArena Battery Test 2.0 methodology, https://www.gsmarena.com/how_we_test_gsmarena_battery_life_test_v2-news-60429.php

**Assessment:** strong model for RetroDojo's battery methodology, especially fixed brightness and standardized workload categories.

## Android Authority

Android Authority similarly sets phones to 200 cd/m², tops off the battery, runs a proprietary looped task app, lets the battery run out, logs results, then separately tracks recharge speed. Source: Android Authority battery methodology, https://www.androidauthority.com/best-of-android-how-we-test-battery-life-912301/

**Assessment:** strong example of repeatable battery testing and transparent test constraints.

## NotebookCheck

NotebookCheck is the closest mainstream analogue to what RetroDojo could emulate. It publishes a detailed methodology covering WiFi via iperf3, SD card transfer tests, display measurements, PWM, response times, thermals, fan noise, power draw, and battery life. For WiFi, it uses an Asus ROG Rapture GT-AXE11000 router, 1-meter distance, iperf3 `-i 1 -t 30 -w 4M -P 10 -O 3`, and tests transmit/receive. Source: NotebookCheck methodology, https://www.notebookcheck.net/How-does-Notebookcheck-test-laptops-and-smartphones-A-behind-the-scenes-look-into-our-review-process.15394.0.html

NotebookCheck also measures displays with X-Rite spectrophotometers, ThorLabs photodetectors, and oscilloscopes; tests PWM/flicker; measures response times; and creates FLIR One Pro thermal images after defined load/idle periods. Same source.

**Assessment:** very rigorous, but lab-heavy. RetroDojo can borrow the structure without needing the full equipment stack.

---

# 2. Broader emulation/community objective methods

## RetroArch overlays/statistics

RetroArch exposes basic on-screen performance visibility: `fps_show`, `memory_show`, `framecount_show`, and a hotkey to toggle "on-screen technical statistics." Source: `libretro/RetroArch:retroarch.cfg:120-132`, `:656-662`.

**Limit:** helps identify obvious slowdowns, but not a full review-grade data pipeline unless captured/logged consistently. Does not measure end-to-end display latency or physical input latency.

## Android ADB telemetry overlap

Public examples of ADB-based telemetry scripts exist. The VCAT web project includes Python functions that read CPU usage via `adb shell cat /proc/stat`, compute deltas, poll GPU utilization via Qualcomm/ARM/MediaTek sysfs paths, parse `dumpsys gfxinfo <package> framestats`, and parse `dumpsys thermalservice` for CPU/GPU/skin/SOC temperatures. Sources: `Video-Codec-Acid-Test-VCAT-Web/vcat-web:vcat_telemetry.py:132-425` (multiple ranges).

Another Android performance monitoring repo (`wwhwhu/Android_Performance_Detection`) logs foreground app, SurfaceFlinger/gfxinfo frame/jank counters, CPU frequencies, meminfo, KGSL GPU stats, thermalservice temperatures, and WiFi link speed via ADB.

**Implication:** RetroDojo's ADB telemetry concept is feasible and overlaps with public techniques, but applying it systematically to retro handheld reviews is still rare — this is the gap.

## Input lag measurement

The rigorous low-cost standard is camera-based. Mick West's original method: record controller and screen together at 60fps+, count frames between the first visible button press and first screen response, convert to milliseconds; recommends CRT/baseline calibration or subtracting display lag. Source: GameDeveloper/Mick West, "Measuring Responsiveness in Video Games," https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games

Digital Foundry uses the same family of methodology with high-speed-camera synchronized comparisons.

**RetroDojo relevance:** this is the biggest gap software telemetry cannot close. ADB can estimate app frame behavior, but cannot measure physical button → emulator input stack → rendered frame → panel response.

---

# 3. White space / defensible differentiation

The clear white space is **handheld-specific, repeatable, public, cross-device telemetry**.

No major retro-handheld-focused channel appears to consistently combine:
1. scripted CPU/GPU/frequency/thermal/battery telemetry,
2. sustained performance/throttling curves,
3. standardized emulator workloads,
4. frame-time/jank measurement for emulator apps,
5. physical input-lag measurement,
6. raw CSV/JSON publication, and
7. cumulative comparison charts across every reviewed device.

Mainstream outlets prove the methods exist (GSMArena/Android Authority for standardized battery; NotebookCheck for WiFi/storage/thermal/display/noise; Digital Foundry for why frame pacing/input latency matter). The retro-handheld niche mostly stops at gameplay footage, synthetic benchmarks, and reviewer impressions.

**The strongest defensible angle:**
> "Every handheld reviewed on the same automated bench: sustained performance, battery drain, thermals, storage, WiFi, frame pacing, and real input latency — with raw data published."

That is credible, useful to buyers, and achievable by a solo creator.

---

# 4. Concrete actionable recommendations

## Priority 1 — Sustained performance + throttling telemetry
**Method:** 20–30 min standardized workloads (3DMark stress, AnTuTu loop, Dolphin/PPSSPP/AetherSX2 scene loop, RetroArch shader stress). Log CPU clocks/usage, GPU usage/clocks, thermal zones, battery %, jank/frame stats.
**Tooling:** mostly ADB/software. **Repeatability:** high.
**Why it matters:** buyers care less about peak Geekbench and more about "does this throttle after 15 minutes of PS2?"

## Priority 2 — Standardized battery drain by workload class
**Method:** fixed brightness (200 nits or documented fallback like 50%), fixed volume, documented WiFi state, run to 20%/10%/shutdown. Categories: light retro, PSP/Dreamcast, PS2/GameCube, Android 3D gaming, idle/sleep drain.
**Tooling:** ADB + optional USB power meter. **Repeatability:** medium-high (needs brightness discipline).
**Model sources:** GSMArena, Android Authority.

## Priority 3 — Emulator frame pacing / jank capture
**Method:** `dumpsys gfxinfo framestats`, SurfaceFlinger frame/jank counters, emulator-reported FPS where available, occasional camera spot-checks for problem devices.
**Tooling:** ADB/software + occasional camera verification. **Repeatability:** medium (rendering paths vary).
**Why it matters:** "60fps" with bad pacing is still bad — Digital Foundry's 33.3ms/16.7ms framing is the right viewer education.

## Priority 4 — Cheap physical input-lag rig
**Method:** phone/camera in slow-mo filming a button/LED and the screen together; ideally an LED wired to a button or small microcontroller/contact switch. Count frames from actuation to first on-screen response.
**Tooling:** phone slow-mo or $50–150 high-speed camera; $10–30 LED/microcontroller parts. **Repeatability:** medium-high with a fixed rig; very valuable.
**Why it matters:** this is the main thing ADB cannot measure — closing this gap is the single biggest differentiator vs. every other niche reviewer.

## Priority 5 — WiFi, storage, and controls mini-suite
**Method:** WiFi via iperf3 at fixed distance/router (transmit/receive); storage sequential/random read/write internal + microSD; controls stick circularity/deadzone/drift + trigger range + haptic strength via accelerometer.
**Tooling:** mostly software; optional router + reference SD card. **Repeatability:** high if standardized.

---

# Prioritized recommendations list

1. **Launch the "RetroDojo Bench Sheet"** for every device: peak scores, sustained score after 20 min, throttle %, max skin/SoC temp, battery drain per workload, WiFi, storage, stick deadzone, and notes.
2. **Publish raw CSV/JSON and methodology pages** so viewers can trust and compare results over time.
3. **Add a slow-mo input-lag rig early** — cheap, visible on camera, differentiates RetroDojo immediately versus every other niche reviewer.
4. **Standardize 3–4 emulator test scenes** across RetroArch, PPSSPP, Dolphin, and PS2 where legally practical.
5. **Create rolling comparison charts**: "best sustained PS2 handheld under $200," "lowest input lag," "best battery per watt," "worst thermal throttle," etc.

---

*Research prepared for RetroDojo's device-bench-suite tooling. Complements `automation-research-findings.md` (ADB/software-side technical findings) with the competitive/market angle: where existing review methodology stops, and where a repeatable automated pipeline + one cheap physical rig can create genuine, defensible differentiation in the retro-handheld review niche.*
