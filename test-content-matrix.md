# Test Content Matrix (Intense Set)

This matrix references **user-owned local ROMs only** under `D:\ROMS\...` (external to this repo). No ROM/BIOs are copied into git.

## Installed + currently usable targets

| System | Emulator/Core on RG476H | Selected intense titles (exact local files) | Why these picks |
|---|---|---|---|
| NES | RetroArch (NES core) | `D:\ROMS\nes\Kirby's Adventure (USA) (Rev 1).zip`<br>`D:\ROMS\nes\Battletoads (USA).zip`<br>`D:\ROMS\nes\Mega Man 4 (USA) (Rev 1).zip` | Heavy sprite/background effects and frequent full-screen action for 8-bit baseline stress. |
| SNES | RetroArch (SNES core) | `D:\ROMS\snes\Star Fox (USA) (Rev 2).zip`<br>`D:\ROMS\snes\Super Mario World 2 - Yoshi's Island (USA) (Rev 1).zip`<br>`D:\ROMS\snes\Killer Instinct (USA) (Rev 1).zip` | SuperFX/SuperFX2 accelerated titles and one of the larger SNES ROMs (KI) for tougher core workload. |
| Genesis / MD | RetroArch (Genesis core) | `D:\ROMS\md\Virtua Racing (USA).zip`<br>`D:\ROMS\md\Sonic 3D Blast (USA, Europe, Korea) (En).zip`<br>`D:\ROMS\md\Ultimate Mortal Kombat 3 (USA).zip` | Includes SVP-enhanced Virtua Racing and larger late-gen carts with heavier visuals/animation. |
| GBA | RetroArch (GBA core) | `D:\ROMS\gba\Need for Speed - Carbon - Own the City (USA, Europe) (En,Fr,De,Es,It).zip`<br>`D:\ROMS\gba\V-Rally 3 (USA) (En,Fr,Es).zip`<br>`D:\ROMS\gba\Duke Nukem Advance (USA).zip` | 3D/racing-heavy and FPS-like GBA workloads that are generally more CPU-demanding than simple 2D titles. |
| Arcade | RetroArch (MAME2003-Plus/FBNeo path) | `D:\ROMS\MAME2003PLUS\sftm.zip`<br>`D:\ROMS\MAME2003PLUS\guwange.zip`<br>`D:\ROMS\MAME2003PLUS\bbakraid.zip` | Large MAME sets with dense effects/sprite throughput for sustained arcade core stress. |
| NDS | DraStic | `D:\ROMS\nds\Ninja Gaiden - Dragon Sword.zip`<br>`D:\ROMS\nds\Simpsons Game, The.zip`<br>`D:\ROMS\nds\Mario & Sonic at the Olympic Winter Games.zip` | Larger NDS images and 3D-heavy scenes likely to pressure CPU/GPU more than lightweight 2D titles. |
| N64 | Mupen64PlusFZ | `D:\ROMS\n64\Conker's Bad Fur Day (NA).z64`<br>`D:\ROMS\n64\Perfect Dark (NA, Rev 1).z64`<br>`D:\ROMS\n64\Resident Evil 2 (NA, Rev 1).z64` | Larger N64 ROMs and known heavier real-world titles with complex scenes/effects. |
| PSP | PPSSPP | `D:\ROMS\psp\God of War - Ghost of Sparta (Europe) (En,Fr,De,Es,It).zip`<br>`D:\ROMS\psp\God of War - Chains of Olympus (USA).iso`<br>`D:\ROMS\psp\Tekken 6 (Europe) (En,Fr,De,Es,It,Ru).zip` | High-end PSP titles with substantial geometry/effects and large assets; useful for upper-bound PPSSPP load. |
| PS1 | RetroArch (PCSX ReARMed) / DuckStation | `D:\ROMS\psx\Tekken 3.PBP`<br>`D:\ROMS\psx\Ridge Racer Type 4.PBP`<br>`D:\ROMS\psx\Crash Team Racing.PBP` | Fighting/racing mix with heavy transparency and full-screen effects; comparison set for `reconsider-ps1-duckstation` todo. |
| Dreamcast | Flycast | `D:\ROMS\dc\Sonic Adventure 2 (USA) (En,Ja,Fr,De,Es).zip`<br>`D:\ROMS\dc\Soulcalibur (USA).zip`<br>`D:\ROMS\dc\Crazy Taxi (USA).zip` | Well-known heavy-load DC titles (open-world, high-poly fighting, dense city streaming); Redream comparison pending its install (Play Store only). |
| Saturn | RetroArch (Beetle Saturn) / Yaba Sanshiro 2 Pro | `D:\ROMS\ss\Virtua Fighter 2 (USA).zip`<br>`D:\ROMS\ss\Daytona USA (USA).chd`<br>`D:\ROMS\ss\Panzer Dragoon (USA) (5S).zip` | Classic Saturn 3D workloads (quads/transparency-heavy); dual-approach test per `setup-saturn` todo. |
| PS2 | AetherSX2 | `D:\ROMS\ps2\Simpsons, The - Hit  Run (USA)1.7z`<br>`D:\ROMS\ps2\Need for Speed - Underground (USA)1.7z`<br>`D:\ROMS\ps2\God of War (USA).7z` | Open-world/racing/action mix; all 3 available titles onboarded. |

## Blocked right now

- GameCube remains blocked by missing standalone emulator app (no Dolphin APK confirmed yet on Odin2EX). BIOS is available.
- All other previously-tracked systems above (NES through PSP) are RG476H-specific findings from an earlier session and have not yet been re-validated on Odin2EX.

## BIOS source convention (flat folder)

BIOS files are sourced from the existing flat folder:

- `D:\bios\`

`Push-TestContent.ps1` maps known filenames to systems (without reorganizing user files):

- **PS1**: `scph*.bin` (for example `scph1001.bin`, `scph5501.bin`)
- **PS2**: `ps2-*.bin` (for example `ps2-0200a-20040614.bin`)
- **Dreamcast**: `dc_boot.bin`, `dc_flash.bin`, `dc_nvmem.bin`
- **GameCube**: `IPL.bin`
- **Saturn**: `sega_101.bin`, `saturn_bios.bin`, `mpr-17933.bin` (added 2026-07-12; the two EU/JP `.ic1` variants present in `D:\bios` are not yet mapped -- not needed for US-region test titles)

Matched BIOS files are pushed to `/storage/emulated/0/ROMs/bios/<system>/` (and for PS1/Dreamcast/Saturn also to `/storage/emulated/0/RetroArch/system/` for RetroArch core usage; PS1 additionally pushes to DuckStation's app-data bios folder, unverified path -- see note below). If no matching BIOS exists for a system, the script prints **"BIOS not found, skipping"**.

### Current blocker status update

- **PS2/GameCube remain blocked by missing standalone emulator apps** on-device (no AetherSX2/NetherSX2, no Dolphin APK). BIOS is available, but emulator app availability is the remaining blocker for these two systems.

### 2026-07-12: Odin2EX onboarded, PS1/Dreamcast/Saturn content live-pushed

New device **Odin2EX** (AYN Odin 2 EX, QCS8550, Android 13, ADB serial `97b7c783`) registered in
`devices.json` -- confirmed via live `adb getprop`, and GPU busy-%/thermal/battery telemetry paths
all confirmed working (Adreno `kgsl-3d0` path, same as other Qualcomm devices). This is a DIFFERENT
device than "Odin 2 Base" referenced in earlier coverage-gap research -- AYN's actual retail naming
is "Odin 2 EX"; treat prior "Odin 2 Base" mentions in this repo's docs as referring to this same
QCS8550-class hardware tier unless a distinct "Odin 2 Base" SKU is confirmed to exist and differ.

Installed via ADB (RetroArch nightly, direct APK) and Obtainium (DuckStation, Flycast -- both
already present in the RJNY Obtainium Emulation Pack, imported via `/sdcard/Download/obtainium-
emulation-pack.json`): **RetroArch, DuckStation, Flycast**. All three confirmed launchable
(`topResumedActivity` check). **Redream and Yaba Sanshiro 2 Pro were NOT installed** (Play
Store-only, not scriptable via ADB/Obtainium -- still open for `reconsider-dreamcast-redream` and
`setup-saturn`).

Content pushed live via `Push-TestContent.ps1 -DeviceName Odin2EX -Systems ps1,dreamcast,saturn`:
9 ROMs (3 each PS1/DC/Saturn, listed in the table above) + PS1 BIOS (6 files) + Saturn BIOS (3 of 6
available files matched) + pre-existing PS2/GC BIOS (unconditional, not filtered by `-Systems`).
All verified present on-device via `adb shell ls`, byte-for-byte size match against source.

Additionally downloaded and manually pushed RetroArch's **Beetle Saturn** (`mednafen_saturn_libretro_
android.so`) and **PCSX ReARMed** (`pcsx_rearmed_libretro_android.so`) cores directly from
`buildbot.libretro.com/nightly/android/latest/arm64-v8a/` to `/storage/emulated/0/RetroArch/cores/`
-- this bypasses RetroArch's in-app Online Updater menu (which needs manual/monkey navigation) for
a fully scripted core install. **NOT YET VISUALLY CONFIRMED** RetroArch recognizes these cores (its
Core Downloader/Load Core menu needs to be checked in-app) -- the device's lock screen (PIN-protected)
blocked screenshot-based verification after a screen-timeout during this session. DuckStation's
first launch went to `SetupWizardActivity` (expected one-time flow, needs manual BIOS-folder/setup
before its `MainActivity` is reachable) -- not yet completed.

**Remaining before a real comparison run can happen (all need the device unlocked/in-hand):**
1. Unlock device, confirm RetroArch's core list shows Beetle Saturn + PCSX ReARMed as loadable.
2. Complete DuckStation's one-time setup wizard (BIOS directory pointed at the pushed PS1 BIOS).
3. Manually load each of the 3 PS1 titles in both RetroArch and DuckStation; load Saturn titles in
   RetroArch (Beetle Saturn); load DC titles in Flycast -- confirm all boot before folding into
   `Invoke-BenchmarkSuite.ps1` runs.
4. DuckStation's actual on-device BIOS folder path was **assumed, not confirmed**
   (`/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files/bios`) -- verify once the
   setup wizard is reachable; DuckStation may use scoped-storage folder picker instead, in which case
   `Push-TestContent.ps1`'s guess won't be picked up automatically and the BIOS path will need to be
   set manually in-app.

### 2026-07-13: PS2 onboarded via AetherSX2; Dreamcast BIOS gap confirmed

User fixed DuckStation's setup wizard and manually installed **Redream** and **Yaba Sanshiro 2 Pro**
(both Play Store-only, not scriptable). User also confirmed PS2 emulators were already installed --
found to be **AetherSX2** (`xyz.aethersx2.android`) plus its Turnip GPU driver variant
(`xyz.aethersx2.tturnip`).

**Dreamcast BIOS gap confirmed as real, not a script bug**: re-checked `D:\bios\` in full -- there
are genuinely no files matching any Dreamcast BIOS naming convention (`dc_boot.bin`, `dc_flash.bin`,
`dc_nvmem.bin`, or common alternates). This isn't something `Push-TestContent.ps1` missed; the
source files don't exist in the user's flat BIOS folder. Flycast can boot many Dreamcast titles
BIOS-free (HLE BIOS mode), so the 3 selected DC titles may still be testable without it, but full
BIOS-accurate comparisons (and any title that hard-requires it) remain blocked until BIOS is sourced.

**PS2 content pushed and BIOS wired in:**
- Launched AetherSX2 once via `adb shell monkey` to trigger its app-data folder creation, confirming
  the exact on-device layout: `/storage/emulated/0/Android/data/xyz.aethersx2.android/files/{bios,games,...}`.
- Pushed all 5 available PS2 BIOS files directly to `.../files/bios/`: `ps2-0200a-20040614.bin`,
  `ps2-0200e-20040614.bin`, `ps2-0200j-20040614.bin`, `ps2-0230a-20080220.bin`, `SCPH-70012.bin`.
- Found `D:\ROMS\ps2\` contains 3 titles: `God of War (USA).7z` (~7.1GB compressed / ~8.5GB
  uncompressed ISO), `Need for Speed - Underground (USA)1.7z` (~1.9GB / ~2.7GB ISO), `Simpsons, The -
  Hit  Run (USA)1.7z` (~694MB / ~2.15GB ISO). Each archive contains a single `.iso`.
- Extracted **Simpsons: Hit & Run** and **NFS: Underground** locally (7-Zip) and pushed the raw ISOs
  directly to `.../files/games/` (confirmed via `adb shell ls`, byte-for-byte match). **God of War
  was skipped** for now -- its 8.5GB uncompressed size makes it a much longer extract/push/test cycle
  and a single title doesn't add much to a 2-title comparison set; can be added later if wanted.
- Added both titles to `test-content.json` (system `ps2`, emulator `AetherSX2`) -- note their
  `devicePath` points at AetherSX2's own app-data games folder (not a shared `/ROMs/ps2/` path,
  since AetherSX2 uses per-app scoped storage rather than a shared ROMs convention like RetroArch).
  These 2 entries were pushed manually this round, not yet via `Push-TestContent.ps1` (which has no
  `ps2` ROM target or 7z-extraction logic yet -- would need both added if this is to be repeatable
  for future devices).
- `D:\ROMS\` was also found to contain `wii\` (1 title, Super Smash Bros. Brawl -- Dolphin already
  validated in an earlier session per checkpoint history) and `xbox\` (original Xbox, 1 title +
  emulator files zip) folders that exist but are outside current scope -- noted for awareness only,
  no action taken.

**Still open before a full PS2/DC comparison run:**
1. Device was locked (`mCurrentFocus=NotificationShade`) at time of push -- RetroArch's core
   recognition (Beetle Saturn/PCSX ReARMed) and actual title-boot across all emulators still needs
   in-person visual confirmation now that the user has the device in-hand.
2. Dreamcast BIOS: source correctly-named files (`dc_boot.bin`/`dc_flash.bin`) if BIOS-accurate
   testing is wanted, or accept Flycast/Redream's BIOS-free HLE mode for the 3 selected titles.
3. God of War (PS2) intentionally not yet onboarded -- revisit if a 3rd PS2 title is wanted.
4. `Push-TestContent.ps1` doesn't yet have `ps2` automation (ROM target dir + 7z extraction) --
   this round's PS2 push was done manually outside the script.

### 2026-07-13 (part 2): Dreamcast BIOS found in D:\bios\dc\ subfolder; GoW added; live app checks

Correction to the above: the Dreamcast BIOS was NOT actually missing -- it lives in a **`D:\bios\dc\`
subfolder** (along with `awbios.zip`, `naomi.zip`, and other arcade-board BIOS files) that the original
flat-folder scan didn't check (only top-level files were scanned, not subdirectories). Confirmed via
byte-signature scan across all top-level files in `D:\bios` (no plaintext DC signature found there)
followed by discovering the `dc\`, `dolphin-emu\`, `PPSSPP\`, `Mupen64plus\`, etc. subfolders that exist
alongside the flat files. `dc_boot.bin` (2097152 bytes), `dc_flash.bin` (131072 bytes), and
`dc_nvmem.bin` (131072 bytes) all confirmed present and correctly named -- exactly what Flycast/Redream
expect.

**Pushed and wired in:**
- All 3 DC BIOS files pushed to `/storage/emulated/0/ROMs/bios/dreamcast/` (shared),
  `/storage/emulated/0/RetroArch/system/` (RetroArch core), and
  `/storage/emulated/0/Android/data/io.recompiled.redream/files/` (Redream's app-private root --
  confirmed writable, unlike Flycast's nested `files/data/` subfolder which returned
  `Permission denied` over ADB).
- Confirmed via Flycast's own `emu.cfg` that it's already configured to read BIOS from the shared
  `/storage/emulated/0/ROMs/bios` path via a granted SAF tree URI -- no app-private BIOS copy needed
  for Flycast.
- Updated `Push-TestContent.ps1`'s `Get-BiosFilesForSystem` to check the `dc\` subfolder under
  `-BiosRoot` for Dreamcast specifically (falls back to flat-root matching if no subfolder exists),
  and added Redream's app-data path to `$biosTargetDirs.dreamcast`.
- Extracted and pushed **God of War** (the 3rd PS2 title, ~8.5GB uncompressed) to AetherSX2's games
  folder -- added to `test-content.json`. All 3 PS2 titles now onboarded.
- Added AetherSX2's own app-data BIOS folder
  (`/storage/emulated/0/Android/data/xyz.aethersx2.android/files/bios`) to `$biosTargetDirs.ps2` and
  added a `ps2` default ROM target dir (AetherSX2's games folder) to `Push-TestContent.ps1` for future
  device onboarding (7z extraction is still a manual pre-step, not scripted).

**Live in-app verification (device unlocked, screenshots taken):**
- **DuckStation**: all 3 PS1 titles auto-recognized in its game list (filenames, sizes, region flags)
  -- ready to test, no further setup needed.
- **AetherSX2**: all 3 PS2 titles auto-recognized with compatibility star ratings -- ready to test.
- **Flycast**: game list came up **empty** ("Your game list is empty / Add Game Folder") despite
  `emu.cfg` already pointing at the correct SAF URI -- the scoped-storage grant likely needs to be
  re-confirmed via the in-app folder picker (one manual tap, can't be scripted around). Not yet ready
  to test until the user does this.
- **Redream**: hit an **"Upgrade to Premium" gate** on first launch -- free tier is "Lite Mode" vs a
  paid "Premium" unlock advertised as HD/full-speed. Tapping "Continue in Lite Mode" did not visibly
  change screens across two attempts (possibly a touch-coordinate/rotation quirk, or the prompt
  persists per-session) -- needs the user to manually get past this and confirm whether Lite Mode
  meaningfully throttles performance (which would make it an unfair comparison point against Flycast
  unless Premium is purchased).
- **RetroArch**: Main Menu loads fine; attempted to navigate to "Load Core" via ADB touch/dpad input
  to confirm Beetle Saturn/PCSX ReARMed show up in the core list, but menu navigation via
  `adb shell input` wasn't reliably registering (RetroArch's Ozone UI may need a real controller/touch
  gesture the emulated input doesn't replicate). The two core `.so` files are physically confirmed
  present via `adb shell ls` on `/storage/emulated/0/RetroArch/cores/`, which is the important thing --
  RetroArch auto-scans this folder, so they should appear next time the user opens "Load Core" in
  person (10-second check).

**Remaining before a full comparison run:**
1. User needs to tap through Flycast's "Add Game Folder" once (SAF picker, needs consent) pointing at
   `/storage/emulated/0/ROMs/dreamcast`.
2. User needs to decide on Redream Premium vs Lite Mode for a fair DC comparison, and get past the
   gate screen.
3. User should do a quick 10-second in-person check that RetroArch's "Load Core" list shows Beetle
   Saturn and PCSX ReARMed.
4. Once above 3 are resolved, all PS1/PS2/Saturn/Dreamcast content and BIOS should be fully ready for
   actual benchmark runs.

### 2026-07-13 (part 3): Root-caused and fixed Flycast's empty Dreamcast game list

User confirmed they'd already granted Flycast the folder permission manually (the one step that
can't be scripted), but the game list stayed empty regardless -- meaning the blocker wasn't the SAF
grant. Fetched Flycast's actual source (`core/imgread/cue.cpp`, `core/imgread/common.cpp` from
`github.com/flyinghead/flycast`) to find the real cause:

- Flycast's `cue_parse()` requires the `.cue` file **and its referenced `.bin` tracks to exist as
  real loose files on disk** -- it resolves sibling `.bin` paths via `getParentPath(file)`, which
  cannot work when the `.cue`/`.bin` set is bundled inside a ZIP archive (no real parent filesystem
  path to resolve from inside a zip stream).
- Our 3 Dreamcast titles (Sonic Adventure 2, Soulcalibur, Crazy Taxi) are all multi-track BIN/CUE
  dumps (3 `.bin` tracks + 1 `.cue` each) -- the standard Redump/No-Intro packaging -- so **zipped
  multi-track BIN/CUE Dreamcast content is fundamentally incompatible with Flycast on Android**,
  independent of folder permissions. Single-file formats (`.chd`, `.gdi`, `.cdi`) are unaffected by
  this and work fine zipped.
- Considered converting to `.chd` (Flycast's natively-preferred, much smaller format via
  `chd_parse`) but could not find a standalone Windows `chdman.exe` build -- MAME's official GitHub
  releases only ship the ROM XML database or full multi-hundred-MB MAME installers, not a standalone
  tools package. Deprioritized as a future improvement, not blocking.

**Fix applied:** extracted all 3 DC zips locally to loose `.bin`/`.cue` files, verified each `.cue`'s
`FILE "..."` references match the extracted filenames exactly (no renaming needed), removed the old
zips from `/storage/emulated/0/ROMs/dreamcast/` on-device, and pushed the loose files in their place
(~1.9GB total). Cleaned up 3 stray empty leftover subfolders from an earlier failed `mkdir -p`
attempt (device shell choked on literal parentheses in ROM titles like `(USA)` even when
double-quoted from PowerShell -- fixed by wrapping the path in single quotes inside the adb shell
arg instead: `adb shell "rmdir '/path/with (parens)'"`).

Updated `test-content.json`'s 3 Dreamcast entries' `devicePath` to point at the new loose `.cue`
files (e.g. `/storage/emulated/0/ROMs/dreamcast/Crazy Taxi (USA).cue`) instead of the stale zip
paths, with a `note` field documenting why.

Redream is explicitly out of scope per the user ("skip redream") -- no further action planned there.

**Still needs a live check:** relaunching Flycast via ADB and re-screenshotting still showed an
empty list, but this may just be an app-side rescan-on-launch quirk (Flycast's SAF game-list scan
may only trigger on the in-app "Rescan Content" button or a fresh "Add Game Folder" tap, not simply
on process relaunch). ADB touch input into Flycast's UI is unreliable right now -- its screenshots
render at 1920x1080 (forced landscape) while the device's physical panel is 1080x1920 portrait with
`mDisplayRotation=ROTATION_0`, so tap coordinates read off a screenshot don't map 1:1 to physical
touch coordinates. **Next step: user should reopen Flycast in person and tap "Rescan Content" (or
just relaunch) to confirm the 3 titles now show up** -- the underlying files are confirmed correct
and in place on-device either way.

### 2026-07-13 (part 4): Flycast confirmed live; RetroArch nightly reinstall fixed input; built apps.odin2ex.json

User confirmed Flycast now shows all 3 Dreamcast titles with correct box art after a rescan --
re-screenshotted and verified directly (Crazy Taxi, Sonic Adventure 2, Soulcalibur all present,
plus it also picked up `DaytonaUSA.chd` from the Saturn folder since Flycast scans multiple ROM
dirs). Fix from part 3 fully validated.

User separately uninstalled the old RetroArch install and updated to a fresh nightly build,
confirming physical controller buttons now work correctly (a prior install had a button/input bug).

### 2026-07-13 (part 5): RG476H "full test" retroactive audit + RetroArch direct-launch re-test on O2EX

User challenged why a "full test suite" couldn't be run on O2EX the way it supposedly was on RG476H.
Audited `results\rg476h-emulator-batch\`, `results\rg476h-ppsspp\`, `results\rg476h-content-validated*\`,
and `results\full-validation-retroarch\` to check what those runs actually captured:

- **DraStic**: reached real gameplay (in-game screenshot) -- has a working file-URI `ACTION_VIEW` handler.
- **PPSSPP**: reached a real game title screen, but only because a monkey tap happened to land on a
  "Recent" game thumbnail -- not a guaranteed/scriptable path.
- **Mupen64PlusFZ**: never left the "Refresh ROMs / Select File / Select Folder" screen in either
  `rg476h-emulator-batch` or `rg476h-content-validated(-2)` runs -- same menu-only limitation seen on O2EX.
- **RetroArch** (`full-validation-retroarch`): never left the Main Menu -- that run used a launcher-only
  intent, no direct-launch extras.
- **Flycast**: `00-launch.png` shows the exact same empty "Add Game Folder" screen we chased on O2EX.
- **RetroArch-PS1 direct-launch via ROM/LIBRETRO/CONFIGFILE** (claimed working in `apps.emulators.json`'s
  notes): no corresponding results folder exists anywhere in `results\` -- the claim was never actually
  captured/verified, only asserted in a comment.

**Conclusion**: the RG476H "full test" was itself a mix of real gameplay (1 confirmed app, 1 lucky app)
and menu/dialog screenshots -- not a uniformly successful gauntlet. It does not prove a general solution
exists; it proves a couple of apps happened to expose a working direct-launch intent on that specific
build.

**Live re-test of the RetroArch ROM/LIBRETRO/CONFIGFILE direct-launch intent on O2EX**: attempted the
exact intent documented as working on RG476H, using `CrashTeamRacing.pbp` (space-free filename, PCSX
ReARMed core, BIOS already present under `RetroArch/system/`). First attempt used the RG476H-documented
core path (`/data/user/0/com.retroarch.aarch64/cores/...`) -- found via `find` that O2EX's nightly build
actually stores cores externally at `/storage/emulated/0/RetroArch/cores/pcsx_rearmed_libretro_android.so`
instead. Corrected the path and retried (also corrected `CONFIGFILE` to the matching external path) --
process launches and stays alive, but stalls indefinitely on a black screen with **0% CPU** (confirmed
via two `/proc/<pid>/stat` samples 4s apart showing identical `utime`/`stime` -- zero ticks, i.e.
genuinely idle, not just slow). Ruled out device sleep as the cause (`dumpsys power` showed
`mWakefulness=Dozing` on one check -- woke the device with `KEYCODE_WAKEUP` and confirmed `Awake`,
re-tested, still stalled identically). No crash/fatal in `logcat --pid=<pid>` -- RetroArch's native
core-loading logging doesn't reach logcat by default, so failure is silent from the ADB side.

**Working conclusion**: the ROM/LIBRETRO/CONFIGFILE direct-launch approach is fragile across RetroArch
build/device combos (see next section for the approach that actually solved this).

## 2026-07-13/14 (part 6) — Three validated O2EX automation methods + expanded overnight research

Following the direct-launch dead-end above, three automation approaches were researched and then
live-validated on O2EX (`97b7c783`), each with independent post-test cleanup verification (never
trusting an agent's self-reported cleanup):

### RetroArch Network Control Interface (NCI) — strongest result

Enabled `network_cmd_enable="true"` / `network_cmd_port="55355"` in `retroarch.cfg`. Direct-launched
content using the **internal** core path (`/data/user/0/com.retroarch.aarch64/cores/...`) — the
external path (`/storage/emulated/0/RetroArch/cores/...`) is the one that black-screens/stalls at 0%
CPU (see part 5 above); this contradicted the RG476H-derived assumption that external was correct.
Verified **real gameplay reached** via `GET_STATUS` for both:
- **PS1**: `CrashTeamRacing.pbp` → `PLAYING playstation,CrashTeamRacing,crc32=d39c2f2`
- **Saturn**: `DaytonaUSA.chd` (Beetle Saturn core) → `PLAYING sega_saturn,DaytonaUSA,crc32=83dea0a1`

Sender pattern (no `adb forward` needed — NCI only listens on-device loopback):
```
adb shell "timeout 3 sh -c 'echo -n <CMD> | nc -u -w1 -q1 127.0.0.1 55355'"
```
Validated commands: `MENU_TOGGLE`, `PAUSE_TOGGLE`, `RESET`, `SAVE_STATE_SLOT`/`LOAD_STATE_SLOT`,
`READ_CORE_MEMORY`. `network_cmd_enable` triple-verified reverted to `false` after testing.

**Version requirement discovered (2026-07-14 research)**: NCI's Android `HAVE_COMMAND` persistence
fix landed 2026-03-25; the `MENU_TOGGLE` runahead-drop fix landed 2026-05-22. **Require a direct/
nightly RetroArch APK from after those dates — never Google Play builds** (years out of date per
RetroArch's own docs). Full compatibility checklist: `docs/retroarch-nci-compatibility.md`.

### `adb shell uinput` virtual gamepad

Discovered physical "Odin Controller" identity via `getevent -lp`/`dumpsys input`: VID:PID
`0x2020:0x0111`. This device's `uinput` binary needs **numeric-string-typed** event codes (e.g.
`"304"` for `BTN_SOUTH`) rather than symbolic labels (`"BTN_SOUTH"`) shown in newer AOSP CTS docs.
**Root cause found in overnight research**: this is an **Android-13/14 vs Android-15+ split in AOSP
itself** (`Event.java`'s numeric-only parser vs. the newer `JsonStyleParser` that accepts both) — not
a device-specific quirk. Branch on Android SDK version, not per-device guesswork. RetroArch,
DuckStation, AetherSX2 all recognized the virtual gamepad and reached EmulationActivity/save-state UI.
Flycast responsive but inconclusive. One run caused a transient RetroArch ANR from aggressive scripted
input — independently verified harmless afterward. Device confirmed ephemeral (vanishes on stdin
close). Full cross-device research, safe-injection-rate table, and a 9-phase device/emulator
certification checklist: `docs/virtual-gamepad-research.md`. Reusable implementation:
`virtual-gamepad/` (see below).

### On-screen overlay touch-tap

Found RetroArch neo-retropad overlay coordinates for 1920x1080 landscape (Up (182,507), Down
(182,695), Left (88,601), Right (276,601), A (1848,601), B (1738,710), X (1738,491), Y (1629,601)).
DuckStation & AetherSX2: high reliability, reached graphics/resolution settings and save-state menus
via touch. Flycast: launch works via long-press tile, but in-menu taps unresponsive on this build.
RetroArch: gameplay touch confirmed via SSIM diffs, but quick-menu toggle unreliable via touch.
**Note: coordinates are resolution/orientation-specific and must be recalibrated per device.**

### Reversibility discipline (hard rule going forward)

One violation occurred this session (leftover `network_cmd_enable=true`), caught only via manual
post-hoc audit. **Rule adopted**: snapshot original state before any device-modifying test,
independently re-verify cleanup after every agent run — never trust self-reported cleanup alone.

### Overnight expansion (2026-07-14) — research + build agents, no live device work

With the user away overnight, five additional workstreams were completed (research + code-writing
only, no live device interaction):

1. **Console expansion research** (Wii/Switch/PS3/Xbox on Android) — `docs/console-expansion-research.md`.
   Verdict: **add Wii now** (Dolphin Android, solid on Snapdragon 8-gen tier); **Switch experimental-only**
   (post-Yuzu/Ryujinx ecosystem unstable — Citron Neo is the one to watch); **PS3/Xbox not viable**
   on Android hardware at all (RPCS3/Xemu/Xenia are desktop-only; Winlator too fragile to benchmark).
2. **Universal virtual gamepad research** — `docs/virtual-gamepad-research.md` (see above).
3. **Virtual gamepad module build** — `virtual-gamepad/` (`rdg_virtual_gamepad.py`,
   `device-profiles.json`, `preflight_validate.py`, sample sequence, README). Schema auto-probe
   (symbolic→numeric fallback), per-device profile system so new handhelds are onboarded via config,
   not code changes. `preflight_validate.py` gates all side-effecting steps behind `--live`.
4. **RetroArch NCI version/requirements verification** — `docs/retroarch-nci-compatibility.md` (see above).
5. **B-roll headless capture pipeline build** — `broll-pipeline/` (`Run-BrollComparisonJob.ps1`,
   `Invoke-BrollCapture.ps1`, `New-BrollComparisonGrid.ps1`, `ConfigPatcher.psm1`,
   `Broll.Common.psm1`, settings-matrix schema + example, README). RetroArch config-patch + NCI
   `LOAD_STATE_SLOT` scene-reproducibility fully implemented; DuckStation/Flycast/AetherSX2 config
   strategies stubbed with clear TODOs (need live-device key discovery). Dry-run mode lets the whole
   pipeline be reviewed without touching a device. Recording via `scrcpy --no-playback --no-window
   --time-limit=N --record=`; comparison grids via ffmpeg `drawtext` + `hstack`/`xstack`.

**Not yet done / needs the user present with a connected device**: live validation of the
virtual-gamepad preflight script's LIVE mode, live validation of the B-roll pipeline end-to-end
(scrcpy/ffmpeg must be confirmed on PATH; DuckStation/Flycast/AetherSX2 config keys need discovery),
and the still-pending `run-o2ex-full-gauntlet` — an actual full `Invoke-BenchmarkSuite.ps1` pass has
never been executed against O2EX.
builds/devices (core storage location varies) and even once paths are corrected it does not reliably
reach gameplay on this O2EX build -- most likely blocked by a scoped-storage-related failure reading the
core `.so` or content file from a raw path, consistent with the same class of issue seen with Flycast's
`file://` VIEW intent. This is not a config typo we can just fix; it needs either root access to confirm
what's actually failing, or an entirely different automation approach (see the input-automation research
task started the same day, and `run-o2ex-full-gauntlet` / `retroarch-direct-launch-o2ex-test` SQL todos).
Investigated why ADB's synthetic `input tap`/`keyevent` commands were landing inconsistently against
RetroArch's Ozone UI: `getevent -i` shows the device has a real **"Odin Controller" gamepad**
(`/dev/input/event8`) as its own hardware input device, separate from ADB's virtual input path --
RetroArch is correctly bound to the physical controller now (confirmed via an on-screen "Virtual
(0/0) not configured, using fallback" toast), which is *why* it was flaky over ADB, not a bug.
Confirmed Beetle Saturn (`mednafen_saturn_libretro_android.so`) and PCSX ReARMed
(`pcsx_rearmed_libretro_android.so`) cores are both present on-device after the user reinstalled
them via RetroArch's in-app Online Updater.

**Realized a full Gauntlet run (telemetry + report) had not actually happened yet** -- content and
cores were onboarded/confirmed-launchable, but no device-specific `apps.json` existed for the
Odin2EX and `Invoke-BenchmarkSuite.ps1` had never been invoked against it. Investigated each
emulator's manifest via `pm dump` to look for a scriptable direct-ROM-launch intent:

- **Flycast**: has a genuine `file://` `ACTION_VIEW` handler on `.MainActivity` (the only one of the
  5 apps that does) -- but actually attempting `am start -a VIEW -d 'file:///.../Crazy Taxi
  (USA).cue'` failed at runtime with `Cannot stat ...`. Root cause: **Android 13 scoped storage
  blocks raw filesystem path access outside an app's own sandbox even when an intent filter exists**
  -- only the in-app SAF folder grant (content:// DocumentsProvider) actually has read access. So
  even Flycast's best-looking manifest doesn't give us a scriptable direct-launch path here.
- **DuckStation, AetherSX2/NetherSX2, RetroArch**: manifests expose MAIN/LAUNCHER only, no
  ACTION_VIEW handler at all (consistent with the same limitation already documented on RG476H).
- **Yaba Sanshiro** (confirmed actual installed package: `org.devmiyax.yabasanshioro2`, the free
  Play Store build -- NOT `.pro` as the backlog note assumed): has a second activity
  (`org.uoyabause.android.Yabause`) declaring both MAIN and VIEW actions, worth a follow-up check,
  but not yet confirmed to actually work -- treated as launcher-only for now.

**Conclusion:** none of the 5 installed emulators can be driven to a specific ROM by script alone on
this device/Android version. Asked the user how to proceed; they opted to build the config now and
run the full suite later. Created **`apps.odin2ex.json`** with launcher-only `launchIntent` entries
for all 5 (RetroArch-PS1, RetroArch-Saturn, DuckStation, Flycast, NetherSX2-PS2, YabaSanshiro2 --
6 entries total since RetroArch is split into two labeled rows for PS1 vs Saturn core reporting),
each documenting exactly which ROMs are staged and ready, and recommending `-SkipMonkey` (manual
play while telemetry logs) as the practical way to actually run a title per README's documented
`-SkipMonkey` mode.

**Not yet done -- this is the actual "full test" still outstanding:**
1. Run `.\Invoke-BenchmarkSuite.ps1 -DeviceName Odin2EX -AppsConfig .\apps.odin2ex.json -SkipMonkey`
   with the user manually loading and playing one title per app during each app's `durationSec`
   window, to produce real `telemetry.csv`/`cooldown.csv`/`framestats.txt`/screenshots per app.
2. Run `New-BenchReport.ps1` (or let the suite auto-call it) to produce `report.md` for the device.
3. Optionally follow up on whether Yaba Sanshiro's `Yabause` activity's VIEW action is actually
   usable for direct launch (untested).