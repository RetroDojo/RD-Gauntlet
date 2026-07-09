# Device Bench Suite Coverage Gaps Research

_Date: 2026-07-08_  
_Scope: research/docs only; no ADB/device operations performed._

## 0) Current launcher behavior in this repo (confirmed)

- `Invoke-BenchmarkSuite.ps1` builds an `am start ...` command only when an app has `launchIntent`; otherwise it falls back to launcher monkey (`monkey -p <pkg> -c android.intent.category.LAUNCHER 1`).
- Even when `launchIntent` exists, any `Error:` output triggers monkey fallback.
- `apps.json` currently has **PPSSPP** and **RetroArch** entries but no `launchIntent`, so they are monkey-launched today.

Evidence:  
- `Invoke-BenchmarkSuite.ps1:388-501, 954-975`  
- `apps.json:31-57`

---

## 1) Gap: RetroArch + PPSSPP direct launch reliability

### Root cause

1. **Suite config gap (confirmed):** no `launchIntent` for PPSSPP/RetroArch in current app config.  
2. **RetroArch intent model mismatch (likely/confirmed):**
   - Current aarch64 package is `com.retroarch.aarch64` (confirmed by APK inspection).
   - Main launcher activity is `com.retroarch.browser.mainmenu.MainMenuActivity` (confirmed).
   - Manifest shows **no ACTION_VIEW intent filter** for RetroArch activities (confirmed), which explains why `am start ... -a VIEW -d file://...` can fail to open content.
3. **PPSSPP supports direct VIEW launch (confirmed):** manifest explicitly exposes `PpssppActivity` for `ACTION_VIEW` with file/content URIs and PSP file patterns (`.iso/.cso/.chd/.pbp/...`).

### Actionable fixes/workarounds

#### 1A. PPSSPP (high-confidence direct intent)

Use explicit component + VIEW URI:

```powershell
adb shell am start \
  -n org.ppsspp.ppsspp/org.ppsspp.ppsspp.PpssppActivity \
  -a android.intent.action.VIEW \
  -d "file:///storage/emulated/0/ROMs/psp/GOWChainsOfOlympus.iso"
```

Proposed `launchIntent` for `apps.json` (not applied in this pass):

```json
"launchIntent": {
  "action": "android.intent.action.VIEW",
  "dataUri": "file:///storage/emulated/0/ROMs/psp/GOWChainsOfOlympus.iso",
  "component": "org.ppsspp.ppsspp/org.ppsspp.ppsspp.PpssppActivity",
  "categories": ["android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"]
}
```

#### 1B. RetroArch (safe launcher intent now; content-open still app-specific)

Reliable launcher command (should open app):

```powershell
adb shell am start \
  -n com.retroarch.aarch64/com.retroarch.browser.mainmenu.MainMenuActivity \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER
```

For direct content-open automation, treat as **speculative** until live-tested on this GammaOS build. Public issue reports indicate RetroArch external launch behavior changed and may require core-path extras (`LIBRETRO`, `ROM`) on recent builds.

### Why `am start -n <pkg>/<activity>` may fail on this environment

- Wrong package variant (e.g., `com.retroarch` vs `com.retroarch.aarch64`) – likely.  
- Activity not exported (general Android rule) – likely in many apps, though RetroArch/PPSSPP launcher activities above are exported.  
- Using ACTION_VIEW where app manifest doesn’t advertise VIEW handling (confirmed for RetroArch manifest).

### Confidence

- PPSSPP package/activity/VIEW support: **Confirmed**  
- RetroArch package/main activity: **Confirmed**  
- RetroArch direct content-open via intent extras in this exact environment: **Speculative until live validation**

---

## 2) Gap: PS1 blocked (RetroArch PSX core missing)

### Root cause

- Existing suite docs already note PS1 remains blocked because current RG476H RetroArch core list did not show a PlayStation core.

Evidence: `README.md:288-290`

### Actionable fixes/workarounds

1. In RetroArch UI, enable Core Downloader visibility if hidden, then install PS1 core via:
   - `Online Updater -> Core Downloader`
   - Install one or both:
     - `Sony - PlayStation (PCSX ReARMed)`
     - `PlayStation (Beetle PSX HW)`
2. Ensure BIOS files exist in RetroArch system dir (suite already pushes to `/storage/emulated/0/RetroArch/system` for PS1 BIOS):
   - `scph5501.bin` (US)
   - ideally also `scph5500.bin` (JP), `scph5502.bin` (EU)
3. Re-run core availability check/live launch test.

### BIOS filename requirements (research)

- PCSX ReARMed doc lists `scph5501.bin` and other accepted BIOS names and warns HLE fallback reduces compatibility.  
- Beetle PSX HW doc lists region BIOS names + md5s and supports override options.

### Confidence

- Core missing as blocker on current device state: **Confirmed (repo docs)**  
- Installation path via Core Downloader + BIOS names above: **Confirmed (official libretro docs)**

---

## 3) Gap: PS2 + GameCube blocked (missing standalone emulator APKs)

### Root cause

- Current suite docs: no standalone PS2/GameCube emulator APK installed, so these systems remain blocked regardless of BIOS availability.

Evidence: `README.md:290`

### Actionable fixes/workarounds

#### 3A. PS2 (NetherSX2)

- NetherSX2 project README states it is a continuation of NetherSX2/AetherSX2 work and publishes APK releases.
- **This specific release was verified via APK manifest parsing in this session** (`NetherSX2-v2.1-4248.apk`):
  - Package: `xyz.aethersx2.android`
  - Main activity: `xyz.aethersx2.android.MainActivity`

Direct launcher command candidate:

```powershell
adb shell am start -n xyz.aethersx2.android/xyz.aethersx2.android.MainActivity
```

> Live-device validation still required per build/version; package name may change in future releases.

#### 3B. GameCube (Dolphin)

From Dolphin Android source:
- App ID/package: `org.dolphinemu.dolphinemu`
- Main launcher activity: `.ui.main.MainActivity` (exported=true)
- Emulation activity is internal (`.activities.EmulationActivity`, exported=false), so direct `am start -n ...EmulationActivity` from shell is not expected to work.

Direct launcher command:

```powershell
adb shell am start -n org.dolphinemu.dolphinemu/org.dolphinemu.dolphinemu.ui.main.MainActivity
```

### Compatibility note for Unisoc/ARM64

- No strict official “Unisoc blocked” statement found in primary docs used here. Treat performance/compatibility risk as **likely hardware-dependent**, requiring live validation on RG476H scenes.

### Confidence

- “Missing APKs” as current blocker: **Confirmed (repo docs)**  
- NetherSX2 package/activity above for checked APK version: **Confirmed (local APK parse)**  
- Dolphin package/activity above: **Confirmed (official source tree)**  
- Broad Unisoc performance expectations: **Likely**

---

## 4) Gap: Dreamcast blocked by empty ROM content folder (not tooling)

### Root cause

- Suite matrix explicitly says Dreamcast blocked because `D:\ROMS\dc` is empty.

Evidence: `test-content-matrix.md` (“Dreamcast/Flycast blocked... D:\ROMS\dc is currently empty”)

### Actionable fixes/workarounds

1. Add at least one legal Dreamcast test title to `D:\ROMS\dc` (e.g., CHD/GDI dump of owned media).
2. Keep BIOS in `D:\bios` using suite-recognized names.
3. Re-run `Push-TestContent.ps1` for `dreamcast` and verify push report.

### BIOS expectations

- Repo script currently recognizes Dreamcast BIOS filenames: `dc_boot.bin`, `dc_flash.bin`, `dc_nvmem.bin` and pushes to both ROM bios path + RetroArch system path.
- Libretro Flycast core docs list `dc/dc_boot.bin` and `dc_nvmem.bin` usage in RetroArch system `dc` directory.

### Minimal legal test-content set (documentation recommendation)

- 1–2 self-dumped Dreamcast games (CHD/GDI preferred for repeatability).  
- BIOS files above from user-owned hardware dumps.  
- No piracy links/sources; only self-dump guidance.

### Confidence

- Empty ROM folder as blocker: **Confirmed**  
- Suite BIOS filename expectations: **Confirmed (repo script)**  
- Flycast BIOS naming (`dc_boot.bin` + dc dir conventions): **Confirmed (libretro docs)**

---

## 5) Gap: high-end device systems not yet set up (Odin 2 Base / RPF2) — 2026-07-08

### Root cause

Not a tooling gap — the bench-suite pipeline (launch, telemetry, monkey load, report) is
system-agnostic and already works for every emulator listed in `apps.emulators.json`. The gap is
purely **missing emulator APKs + BIOS + legal ROM dumps** for systems that weren't worth attempting
on the lower/mid-tier devices tested previously (RG476H/RPC6-class), but that the higher-end
**AYN Odin 2 Base** (SD 8 Gen 2 / Adreno 740) and **Retroid Pocket Flip 2 / RPF2** (SD865 / Adreno
650 — corrected from an earlier assumption of SD 8 Gen 2/3; RPF2 is actually the same tier as
RP5/RP Mini, see Retro Game Corps ROCKNIX guide, March 2026) can realistically attempt.

Everything below requires the user to source content/APKs directly (same self-dump-only policy as
the Dreamcast section above) before it can be added to `apps.emulators.json` and run through
`Invoke-BenchmarkSuite.ps1`.

### Actionable fixes/workarounds — per system

| System | Emulator | APK source | BIOS/keys needed | Target device(s) | Benchmark titles |
|---|---|---|---|---|---|
| Wii U | Cemu (Android port) | `github.com/SSimco/Cemu/releases` | None for unencrypted `.rpx`/`.wua`; `keys.txt` for encrypted | Odin 2 Base primary; RPF2 as a stretch data point | Mario Kart 8, Wind Waker HD, BOTW (Wii U) |
| PS Vita | Vita3K | `github.com/Vita3K/Vita3K-Android/releases` (tag `continuous`) | `PSP2UPDAT.PUP` + `PSVUPDAT.PUP` firmware installed in-app; Turnip driver recommended | Odin 2 Base primary; RPF2 limited to simple titles | Persona 4 Golden, Uncharted: Golden Abyss |
| Saturn | Yaba Sanshiro 2 Pro (standalone) / RetroArch Beetle Saturn (core) | Play Store (`org.devmiyax.yabasanshioro2.pro`) / libretro nightly buildbot | `sega_101.bin` + `mpr-17933.bin` | RPF2 → YBS2 standalone; Odin 2 Base → Beetle Saturn core (more demanding/accurate) | Any CHD dump; community treats Saturn as a difficult-system stress test |
| Switch | Eden | `eden-emu.dev` (self-hosted; GitHub repo is Nintendo-DMCA'd/451) or Obtainium | Turnip driver via Eden's built-in Driver Manager | Odin 2 Base only | Celeste (2D sanity check) → Super Mario Odyssey (gold-standard benchmark) → BOTW (heavy 3D stress test) |
| Xbox 360 | X360 Mobile | `github.com/Ashnar2602/X360-Mobile---OFFICIAL/releases` or `x360mobile.com` | None documented | Odin 2 Base only (SD 8 Gen 2 recommended minimum; RPF2/SD865 below spec) | One light/indie title + one AAA bracket title (Halo 3 or Gears of War) |
| PS3 | RPCSX-UI-Android | `github.com/RPCSX/rpcsx-ui-android` | Unknown — pre-alpha | Odin 2 Base only, investigative/Tier-3 only | N/A — expect instability, document current state only |

Two systems already validated (Dolphin/Wii, Flycast/Dreamcast) are **not** included above since the
tooling already handles them; the Wii pass just needs new test runs with motion-control mapping
and VBI Skip notes (see prior GC section), and Dreamcast is purely blocked on ROM/BIOS sourcing
(user handling separately) as described in section 4 above.

Two comparison/upgrade opportunities also surfaced (lower priority, not blocking anything):
- **Redream** (Play Store, `io.recompiled.redream`) as a standalone alternative to Flycast for
  Dreamcast — community now prefers it, has auto-frameskip.
- **DuckStation** (Play Store, `com.github.stenzek.duckstation`) as a standalone alternative to
  RetroArch/PCSX ReARMed for PS1 — better enhancements (PGXP, upscaling).

### Legal/distribution notes

- **Switch (Eden)**: legally volatile — Nintendo has DMCA'd the GitHub repos of every major
  Yuzu-lineage fork (Eden, Kenji-NX). Verify current download/legal status immediately before each
  test session; this changes month to month. Do **not** use EggNS or DamonSwitch — confirmed
  malware/GPL violations per EG Wiki.
- **PS3/RPCS3-Android**: officially discontinued; RPCSX-UI-Android is the actively developed
  successor but is pre-alpha.
- All BIOS/firmware/game content must come from the user's own legally-owned hardware dumps —
  same policy as the rest of this document.

### Confidence

- Odin 2 Base / RPF2 chipset identification: **Confirmed** (Retroid official product page;
  Retro Game Corps ROCKNIX guide, March 2026)
- Per-system emulator maturity/recommendation: **Confirmed** via Retro Game Corps Android Starter
  Guide (updated Feb 10, 2026) and EG Wiki (live, 2026) — see full research report for citations
- Specific performance-tier claims (e.g., "BOTW playable at 720p/30fps") are **inferred** from
  community consensus, not fresh hardware-specific benchmarks on these exact two devices — this
  repo's own benchmark runs will be the first first-party data point once tests are executed

---

## Low-risk repo changes that could be made now (not applied in this pass)

1. Add PPSSPP `launchIntent` to `apps.json` (high-confidence, based on official manifest).  
2. Optionally add RetroArch launcher-only `launchIntent` (MAIN/LAUNCHER) to reduce monkey randomness for app start; keep monkey for workload unless explicit content-open automation is validated.  
3. Keep all such changes flagged “requires live-device validation” before trusting benchmark comparability.

_No `.ps1`/`.json` modifications were made in this run._

---

## Brief web_search-based methodology check (competitive/best-practice)

- **GSMArena-style:** standardized battery testing with controlled brightness and repeatable workload classes is the key pattern to emulate for comparability.  
- **NotebookCheck-style:** explicit methodology + repeatable network/thermal/noise procedure improves trust and cross-device comparison quality.  
- **Retro-handheld channels:** generally more manual/qualitative in published workflows; opportunity remains for stricter, script-backed emulator methodology with explicit BIOS/core provenance.

(See sources list for links.)

---

## Sources

### Repo-local evidence
- `Invoke-BenchmarkSuite.ps1:388-501,954-975`
- `apps.json:31-57`
- `apps.emulators.json`
- `README.md:280-290`
- `test-content-matrix.md`
- `Push-TestContent.ps1:167-194,289-295`

### Primary external sources
- PPSSPP Android manifest:  
  https://raw.githubusercontent.com/hrydgard/ppsspp/0335e5e6a98a9578a2a2b6a7698905d706e4ca82/android/AndroidManifest.xml
- PPSSPP Android build config (`applicationId`):  
  https://raw.githubusercontent.com/hrydgard/ppsspp/0335e5e6a98a9578a2a2b6a7698905d706e4ca82/android/build.gradle.kts
- RetroArch Android manifest:  
  https://raw.githubusercontent.com/libretro/RetroArch/a419c18439dc220970ed641de8873708f0293f3a/pkg/android/phoenix/AndroidManifest.xml
- RetroArch Android build flavors (`.aarch64` suffix):  
  https://raw.githubusercontent.com/libretro/RetroArch/a419c18439dc220970ed641de8873708f0293f3a/pkg/android/phoenix/build.gradle
- RetroArch nightly APK index (LakkaTeam/libretro builds):  
  https://buildbot.libretro.com/nightly/android/
- RetroArch external launch behavior discussion:  
  https://github.com/libretro/RetroArch/issues/17433
- Libretro core downloader guide:  
  https://docs.libretro.com/guides/download-cores/
- Libretro PCSX ReARMed BIOS requirements:  
  https://docs.libretro.com/library/pcsx_rearmed/
- Libretro Beetle PSX HW BIOS requirements:  
  https://raw.githubusercontent.com/libretro/docs/master/docs/library/beetle_psx_hw.md
- Libretro Flycast core docs (BIOS/system dir):  
  https://docs.libretro.com/library/flycast/
- Dolphin Android app manifest (`.ui.main.MainActivity` and exported flags):  
  https://raw.githubusercontent.com/dolphin-emu/dolphin/f93f69a1e59e02d31d819db7064c817b479ff83b/Source/Android/app/src/main/AndroidManifest.xml
- Dolphin Android build config (`applicationId`):  
  https://raw.githubusercontent.com/dolphin-emu/dolphin/f93f69a1e59e02d31d819db7064c817b479ff83b/Source/Android/app/build.gradle.kts
- NetherSX2 continuation/releases README:  
  https://raw.githubusercontent.com/Trixarian/NetherSX2-patch/75fc270d50b8c1ba81daf874635471b8d07be09e/README.md
- Nether patch repo evidence of package/activity patch target (`xyz.aethersx2.android/MainActivity`):  
  https://github.com/Trixarian/NetherSX2-patch/blob/75fc270d50b8c1ba81daf874635471b8d07be09e/patches/patch_root_storage.py
- AetherSX2 Play Store removal reporting + successor context:  
  https://www.timeextension.com/news/2024/03/ps2-emulator-that-triggered-death-threats-is-finally-yanked-from-google-play-store
- Android exported-component behavior docs:  
  https://developer.android.com/guide/topics/manifest/activity-element#exported
  https://developer.android.com/about/versions/12/behavior-changes-12#exported

### Additional methodology references (web-search pass)
- GSMArena battery methodology context:  
  https://www.gsmarena.com/battery-test_procedure-and-scores
- NotebookCheck methodology context:  
  https://www.notebookcheck.net/How-does-Notebookcheck-test-laptops-and-smartphones-A-behind-the-scenes-look-into-our-review-process.15394.0.html
