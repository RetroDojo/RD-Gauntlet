# RetroArch Network Control Interface (NCI) — Compatibility Requirements

Verified 2026-07-14 via source-level research against the `libretro/RetroArch` repo. This document
defines the compatibility envelope for using NCI as RD-Gauntlet's primary RetroArch automation
method, and a pre-flight checklist to run against any new test device.

## Bottom line

**Do not treat NCI as universally reliable across all Android RetroArch installs.** It only works
consistently if:
- You control the RetroArch build (direct/nightly APK, **not** Google Play — Play Store builds are
  years out of date per RetroArch's own install docs).
- The build is from **after 2026-03-25** (Android `HAVE_COMMAND` persistence/listener fix,
  commit `c9f7eb0`) — required for `network_cmd_enable` to even persist/register on Android.
- If relying on `MENU_TOGGLE`, the build must be from **after 2026-05-22** (runahead single-frame-pulse
  fix, commit `708256e`) or `MENU_TOGGLE` may be dropped under single-instance runahead.

Our O2EX test build (nightly, validated 2026-07-13) worked correctly for `GET_STATUS`,
`MENU_TOGGLE`, `PAUSE_TOGGLE`, `RESET`, `SAVE_STATE_SLOT`/`LOAD_STATE_SLOT`, `READ_CORE_MEMORY` — so
it postdates both fixes. **Any additional test device must be checked against this same bar before
NCI is trusted for it.**

## Key facts

- **Default port**: `55355` (UDP). Config keys: `network_cmd_enable="true"`,
  `network_cmd_port="55355"`. No password/auth mechanism exists — NCI is plain, unauthenticated UDP.
- **Android build flags required**: `-DHAVE_NETWORKING -DHAVE_NETWORK_CMD -DHAVE_COMMAND`. The
  `v1.22.2` tagged stable Android build was missing `-DHAVE_COMMAND`, meaning the setting wasn't
  even registered/persisted on that version.
- **Foreground requirement**: NCI is polled inside RetroArch's runloop (`command_network_poll()`),
  not a background Android service. **Do not background/minimize RetroArch during NCI-driven runs**
  — Android's process lifecycle/battery restrictions could stop the poll loop even if the socket
  stays bound. Keep RetroArch foregrounded for all benchmark control.
- **Port conflicts**: if bind fails (e.g., another instance/app already on 55355), RetroArch just
  logs a failure — automation must verify via a `GET_STATUS`/`VERSION` handshake rather than
  assuming success.
- **`GET_STATUS` pause ambiguity**: known issue (#12379) — if "Pause Content When Menu Is Active" is
  on, `GET_STATUS` can report `PLAYING` even though the menu (not gameplay) is active. Don't treat
  `PLAYING` alone as proof gameplay is visible; corroborate with `CRC32`/content name match and, if
  possible, a screenshot.
- **Screenshot command exists**: NCI supports `SCREENSHOT` directly (writes to RetroArch's configured
  screenshot directory) — can avoid `adb shell screencap` if directory/timing is handled.
- **Security**: unauthenticated UDP means anything able to reach the port (e.g., other apps on-device)
  can send commands including `QUIT`/`WRITE_CORE_MEMORY`. Policy: **NCI off by default, enabled only
  during automated test runs, disabled immediately after** (this matches the discipline already
  established this session).

## Command reference (most useful for benchmark automation)

| Command | Purpose |
|---|---|
| `VERSION` | Handshake / sanity check |
| `GET_STATUS` | Returns `PLAYING/PAUSED/CONTENTLESS <system>,<content>,crc32=<hex>` — primary verification mechanism |
| `GET_CONFIG_PARAM <key>` | Query limited config values (video_fullscreen, savefile_directory, savestate_directory, etc.) |
| `LOAD_STATE_SLOT <n>` / `SAVE_STATE_SLOT <n>` | Deterministic scene reproducibility (used for B-roll and repeatable testing) |
| `PAUSE_TOGGLE` / `FRAMEADVANCE` | Timing control |
| `MENU_TOGGLE` | Requires build after 2026-05-22 for reliability under runahead |
| `RESET` / `CLOSE_CONTENT` | Cleanup |
| `READ_CORE_MEMORY <hexaddr> <n>` / `WRITE_CORE_MEMORY` | Memory verification/patching (prefer over `READ/WRITE_CORE_RAM`, which are cheevos-address-based and known-broken since 2024, issue #16392) |
| `SCREENSHOT` | Triggers RetroArch's own screenshot capture |

## Pre-flight compatibility checklist (run against any new device)

1. **Install source**: confirm direct/nightly APK from retroarch.com/buildbot, not Google Play. If
   F-Droid, verify the packaged commit is after 2026-03-25.
2. **Version check**: RetroArch → Settings → Information → System Information; confirm build
   date/commit postdates the required fixes (2026-03-25 minimum, 2026-05-22 if `MENU_TOGGLE` needed).
3. **Enable NCI**: set `network_cmd_enable="true"` + `network_cmd_port="55355"` in `retroarch.cfg` (or
   via Settings → Network → Network Commands), restart RetroArch once, confirm the setting persisted
   (re-open settings, check it's still on) — this specifically validates the `HAVE_COMMAND` fix is
   present.
4. **Keep foregrounded**: disable any battery/game-mode background restriction that could suspend
   RetroArch during a test run.
5. **Port check**: use a unique port if multiple device/instances may run concurrently.
6. **Handshake**: send `VERSION`, expect a version string response within timeout.
7. **Status check**: send `GET_STATUS`, expect `CONTENTLESS` (no content) or `PLAYING/PAUSED ...`
   with correct system/content/CRC once content is loaded.
8. **Determinism check**: `PAUSE_TOGGLE` → `FRAMEADVANCE` → `SAVE_STATE_SLOT 9` → `LOAD_STATE_SLOT 9`,
   confirm responses and that the state restore visibly worked (screenshot diff).
9. **Memory check** (if used): `READ_CORE_MEMORY <addr> <n>` returns real bytes, not
   `-1 no memory map defined`.
10. **Screenshot check** (if used): `SCREENSHOT`, confirm file appears in the configured directory.
11. **Teardown**: set `network_cmd_enable="false"` and confirm it saved — never leave NCI on after a
    test run.

## Sender pattern (validated on O2EX)

Run `nc` from the on-device shell targeting loopback directly — avoids `adb forward` ambiguity since
NCI only listens on-device:

```
adb shell "timeout 3 sh -c 'echo -n <CMD> | nc -u -w1 -q1 127.0.0.1 55355'"
```

## Sources

RetroArch source (`command.c`, `command.h`, Android `Android.mk`), RetroArch install docs
(`docs/guides/install-android.md`), RetroArch NCI docs
(`docs/development/retroarch/network-control-interface.md`), GitHub PRs #10073, #12105, #13668,
#17961, #18862, #19052, issues #12379, #16392, and the libretro.com blog post on Play Store vs
direct-download Android build differences.
