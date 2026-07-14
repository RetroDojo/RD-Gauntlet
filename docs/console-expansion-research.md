# Console Expansion Research — Wii / Switch / PS3 / Xbox on Android

Research conducted 2026-07-14 to evaluate adding Wii, Switch, PS3, and Xbox/360 to the RD-Gauntlet
test matrix, targeting Snapdragon 8-gen-class Android handhelds (Odin2/2EX, Retroid Pocket, similar).

## Executive recommendation table

| System | Android viability (2026) | Recommendation |
|---|---:|---|
| **Nintendo Wii** | Good on Snapdragon 8-gen tier, esp. 1x-2x internal res | **Add now** |
| **Nintendo Switch** | Technically possible but unstable post-Yuzu/Ryujinx ecosystem | **Monitor / experimental only, not core matrix** |
| **PlayStation 3** | No credible native Android emulator | **Not viable** |
| **Xbox / Xbox 360** | No native Android path; Winlator too fragile for benchmarking | **Not viable for benchmark matrix** |

## 1. Nintendo Wii — Dolphin Android — ADD NOW

- Official Dolphin (dolphin-emu/dolphin) is active in 2026 with in-tree Android support. Use this,
  not MMJR/MMJR2 forks (legacy/experimental curiosity only — smaller maintenance footprint).
- **Performance**: 1x/2x internal resolution is a solid baseline on Snapdragon 8-gen handhelds; 3x+
  is title/driver-dependent. Vulkan is generally preferred over GL on Adreno, but worth testing both.
  Motion-heavy Wii titles are harder to automate (Wiimote IR/motion mapping) — pick at least one
  classic-controller/GameCube-compatible title as the benchmark baseline, not a motion-only game.
- **Config automation**: Yes — same INI-backed model as desktop Dolphin (`Dolphin.ini` [Core]
  `GFXBackend`; `GFX.ini` [Settings] `InternalResolution`, `MSAA`; `WiimoteNew.ini` `Wiimote1`
  `Source`). Push/edit config files via ADB, then force-stop/relaunch to apply.
- **Direct launch**: No NCI-style remote control, but there IS an app-link/deep-link scheme:
  `dolphinemu://app/play/<channelId>/<gameId>` resolved via a **cached game ID** (must scan library
  first — no arbitrary-ROM-path launch). Example:
  `adb shell am start -a android.intent.action.VIEW -d "dolphinemu://app/play/0/RMGE01"`.
  `EmulationActivity` itself is `exported="false"`, so it can't be targeted directly.
- **Input binding**: Uses Android `InputDevice`/`KeyEvent`/`MotionEvent` + native controller
  interface; does NOT appear to have RetroArch's "physical controller overrides binding" issue as a
  global problem. Preconfigure mappings for repeatability; don't rely on first-detected device order.

## 2. Nintendo Switch — MONITOR / EXPERIMENTAL ONLY

- Yuzu shut down 2024 (Nintendo lawsuit, $2.4M settlement, repos pulled). Ryujinx similarly ceased
  official availability in 2024.
- **Citron Neo** (citron-neo/emulator) is the most active 2026 successor with Android APKs
  (mainline release builds available), but Android support continuity is explicitly uncertain per
  its own site ("nobody here really wants to update it"). Requires Android 13+, Vulkan, 6GB+ RAM.
  Has first-run controller auto-mapping (assigns default mapping to player 1 if none configured).
- **Strato** (Skyline continuation) exists but last push observed 2024-09; not a dependable target
  right now, worth monitoring for a release-cadence resumption.
- Suyu/Sudachi/Mandarine: no stable official presence found (Suyu returned HTTP 451/legal
  restriction; Sudachi domain is "coming soon"; Mandarine not found).
- **Verdict**: legally chilled, fast-moving, inconsistent ecosystem — not clean enough for a
  repeatable automated benchmark yet. Good for a standalone "state of Switch on Android" video, not
  core RD-Gauntlet scoring. Revisit if Citron Neo or Strato stabilize.

## 3. PlayStation 3 — NOT VIABLE

- RPCS3 is Windows/Linux/macOS/FreeBSD only — no Android port, official or unofficial found.
- Architecturally poor fit even hypothetically: Cell PPE+SPU emulation and RSX GPU emulation are
  desktop-CPU/GPU-class demanding; Android handheld SoCs are thermally constrained and lack the
  headroom. Not worth pursuing.

## 4. Xbox / Xbox 360 — NOT VIABLE for the benchmark matrix

- **Xemu** (original Xbox): Windows/macOS/Linux (incl. some ARM Linux) — no native Android app.
  Requires MCPX boot ROM/BIOS/HDD image (must be dumped from real hardware, not distributable).
- **Xenia** (360): recommends x86 AVX/AVX2 CPU + GTX 980 Ti-class GPU; explicitly not Android-viable
  even via translation layers — ARM handhelds are the wrong CPU architecture entirely for Xenia's
  assumptions.
- **Winlator** (Wine + Box86/Box64 Android compat layer) is active and popular (v11.1, 2026), but
  running an x86 desktop emulator INSIDE Wine/Box64 ON Android adds too many overhead/failure-point
  layers for fair, repeatable benchmarking — automation model is also fundamentally different
  (automating the Winlator container/shortcuts, not the emulator directly; config lives in Wine
  prefixes). Possible one-off "can Winlator run Xbox emulators" novelty video, not a matrix candidate.

## Sources
Dolphin GitHub/Android source tree (AppLinkHelper.kt, AppLinkActivity.kt, Settings.kt,
IntSetting.kt, StringSetting.kt, ControllerInterface.kt, MappingCommon.kt, AndroidManifest.xml);
Citron Neo site/repo/manifest; Strato repo/README/compat-list; RPCS3 README/BUILDING.md; Xemu
docs (download/required-files/cli); Xenia README/Quickstart wiki; Winlator README/releases; The
Verge (Yuzu settlement, 2024-03-04).
