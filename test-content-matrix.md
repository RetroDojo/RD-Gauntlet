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

## Blocked right now

- **Dreamcast / Flycast**: blocked. `D:\ROMS\dc` is currently empty, so no valid Dreamcast content can be pushed/launched.
- Dreamcast testing also requires user-supplied BIOS dumps where applicable.
- This suite does **not** source/download BIOS or copyrighted ROMs.

## BIOS source convention (flat folder)

BIOS files are sourced from the existing flat folder:

- `D:\bios\`

`Push-TestContent.ps1` maps known filenames to systems (without reorganizing user files):

- **PS1**: `scph*.bin` (for example `scph1001.bin`, `scph5501.bin`)
- **PS2**: `ps2-*.bin` (for example `ps2-0200a-20040614.bin`)
- **Dreamcast**: `dc_boot.bin`, `dc_flash.bin`, `dc_nvmem.bin`
- **GameCube**: `IPL.bin`

Matched BIOS files are pushed to `/storage/emulated/0/ROMs/bios/<system>/` (and for PS1/Dreamcast also to `/storage/emulated/0/RetroArch/system/` for RetroArch core usage). If no matching BIOS exists for a system, the script prints **"BIOS not found, skipping"**.

### Current blocker status update

- **Dreamcast/Flycast remains blocked** even with BIOS present, because `D:\ROMS\dc` is still empty (no testable content).
- **PS1 via RetroArch remains unvalidated** on current RG476H state: BIOS is now available/pushed, but RetroArch core list testing did not show a Sony PlayStation core (`PCSX-ReARMed`/`Beetle PSX`) in the installed cores list.
- **PS2/GameCube remain blocked by missing standalone emulator apps** on-device (no AetherSX2/NetherSX2, no Dolphin APK). BIOS is available, but emulator app availability is the remaining blocker for these two systems.