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

## Blocked right now

- **PS2/GameCube remain blocked by missing standalone emulator apps** on-device (no AetherSX2/NetherSX2, no Dolphin APK). BIOS is available, but emulator app availability is the remaining blocker for these two systems.
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