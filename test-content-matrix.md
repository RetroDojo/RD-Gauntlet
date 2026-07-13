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