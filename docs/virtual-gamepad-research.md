# Universal Virtual Gamepad (`adb shell uinput`) — Cross-Device Research & Validation Methodology

Research conducted 2026-07-14, source-level (AOSP `system/core`, `frameworks/base/cmds/uinput`,
`system/sepolicy`) to determine how far `adb shell uinput` generalizes as RD-Gauntlet's universal,
root-free virtual-gamepad automation layer beyond the one Odin2EX device it's been validated on.

## Executive summary

`uinput` is a strong candidate for RD-Gauntlet's **default root-free virtual-gamepad layer**, but
**not safe to assume universally compatible without a per-device preflight**. AOSP intends this to
work (`/dev/uinput` mode 0660 owned by `uhid:uhid`, `shell` in the `AID_UHID` group, SELinux allows
`shell` rw on `uhid_device`) — but device firmware (vendor `ueventd.rc`, SELinux policy, kernel
config, Android branch age) can all break it. **Our Odin2EX success is encouraging, not proof of
universality** — no public device-specific compatibility matrix exists for Retroid/Odin/AYANEO/RG-
class handhelds; each new device must be certified via the checklist below.

Treat `uinput` as excellent for **deterministic menu navigation and benchmark setup**, but **not
frame-perfect/TAS-grade input** — AOSP's own docs say events may land "a few milliseconds late" and
scheduling is Android-`Handler`-based (millisecond, not nanosecond, precision) even though delays
are specified in nanoseconds.

## 1. Cross-device compatibility variance — root cause of failure modes

Possible breakage points on a new device, in order of likelihood:
1. Kernel lacks `CONFIG_INPUT_UINPUT` or has too old an interface.
2. `/dev/uinput` missing (kernel module/device node absent).
3. Vendor `ueventd.rc` overrides default permissions so `shell` can't open it.
4. Vendor SELinux policy blocks `shell` despite filesystem group permissions.
5. AOSP `uinput` command missing/replaced by vendor firmware.
6. Kernel uinput version < 5 — AOSP's own JNI explicitly rejects this (`UI_GET_VERSION` check).

**Action**: never assume; run Phase A of the validation checklist (below) on every new device.

## 2. The JSON schema quirk — now fully explained

This is the root cause of the numeric-vs-symbolic schema issue found on the O2EX:

| Android version | Schema accepted |
|---|---|
| **Android 13 / 14** | **Numeric only** — `Event.java`'s `readInt()`/`readIntList()` call `Integer.decode()` on stringified values; no symbolic label support at all. |
| **Android 15 / mainline** | **Both** — new `JsonStyleParser` tries `Integer.decode()` first, falls back to symbolic label lookup (`EV_KEY`, `BTN_A`, `UI_SET_EVBIT`, etc.) |

Our O2EX is Android 13 — this is **not a device-specific quirk, it's a documented Android-version
behavior**. This means: **branch on Android SDK version, not per-device guesswork.** Devices on
Android 13/14 need numeric schema; Android 15+ can use either (prefer symbolic for readability, but
numeric always works as a universal fallback).

Recommended detection order (cache per device build fingerprint):
1. Try a tiny symbolic registration probe.
2. Verify via `getevent -p`.
3. If it fails or malformed-data errors appear in logcat, retry with numeric schema.
4. Cache `uinput_schema = symbolic | numeric | unsupported` keyed by `ro.build.fingerprint`.

## 3. Input latency/timing — realistic expectations

Event path: `host script → ADB transport → shell stdin → uinput process → /dev/uinput → kernel
evdev → Android InputReader/InputDispatcher → emulator app → emulator polling loop`.

- Real physical/built-in controller: lowest, most stable latency.
- `uinput` over **persistent USB ADB**: usually close enough for automation; some ADB/shell/scheduler
  jitter. **Use USB ADB for official benchmark runs.**
- `uinput` over **Wi-Fi ADB**: more variable (network jitter) — dev/iteration only, not production.
- `adb shell input`: goes through `InputManagerGlobal.injectInputEvent` at the framework level, not
  a real controller identity — different pipeline, useful for touch but not a gamepad substitute.

**Frame-accuracy verdict**: good for menu nav/settings toggling/scene start-stop; **do not use for
"hold exactly N frames" or speedrun/TAS-style precision** — use RetroArch's own
runahead/TAS/movie/NCI mechanisms for that instead, or empirically measure actual app-observed
timing before trusting any frame-accurate claim.

## 4. Event-ordering / reliability at scale — safe injection rates

Documented AOSP failure modes: events queued without `updateTimeBase` after a long wait get flushed
immediately (kernel event buffer overrun/drops); events sent before device registration completes
can be dropped; missing `EV_SYN/SYN_REPORT` can hide state transitions from apps; unreleased button
presses leave menus/games stuck; over-aggressive scripting can overrun an emulator's per-frame input
poll and cause ANRs (matches the transient RetroArch ANR observed this session).

**Recommended timing table**:

| Use case | Delay |
|---|---:|
| After device registration | 750-1500 ms |
| Button down → up hold | 40-80 ms |
| Between menu actions | 120-250 ms |
| Between settings-screen transitions | 300-750 ms |
| Stress-test lower bound tiers | 16.7 / 33 / 50 ms |
| Production default | Slowest tier with zero drops in preflight (start at ~200ms/action) |

**Reliability rules**: keep ONE persistent `adb shell uinput -` session (never spawn per-button
processes); register once; wait for `getevent -p`/`dumpsys input` visibility before sending events;
use the `delay` command for intra-sequence timing, not host-side sleeps alone; call `updateTimeBase`
before every new phase after screenshots/app-launches/waits; never enqueue large batches without an
intermediate verification step.

## 5. Cross-emulator autoconfig binding — expectation table

Any emulator using Android's standard `InputDevice`/`KeyEvent`/`MotionEvent` stack (`SOURCE_GAMEPAD`/
`SOURCE_DPAD`/`SOURCE_JOYSTICK`) should see a `uinput` virtual pad as a first-class controller.

| Emulator | Expected visibility | Notes |
|---|---|---|
| RetroArch | High | Verified on O2EX; uses NDK `AInputQueue`/`AInputEvent` + `input_autoconfigure_connect` |
| DuckStation | High | Verified on O2EX; may require binding/profile persistence |
| AetherSX2 | High | Verified on O2EX; app unmaintained — validate per fork/build |
| PPSSPP | High | Standard Android controller APIs (unverified live, high confidence) |
| Flycast | High | Standard Android/SDL-style input (unverified live, high confidence) |
| Dolphin | Medium-high | Controller input should work; Wii Remote/raw-adapter modes are separate paths, not satisfied by a uinput pad |
| Switch emulators | Medium/unknown | Custom input layers/profile expectations vary; treat as unverified per app |

**Caveats**: SDL-based builds may require a mapping/GUID entry; apps may ignore unknown controllers
until manually bound once; declare BOTH button and axis capabilities in registration; raw USB
HID/libusb paths will NOT see a `uinput` device (it's an evdev device, not a real USB HID endpoint).

## 6. Validation checklist — run per (device × Android build × emulator × emulator version)

**Phase A — Device capability probe** (read-only):
```
adb shell getprop ro.build.fingerprint / ro.build.version.release / ro.build.version.sdk
adb shell id                      # look for uhid group
adb shell command -v uinput
adb shell ls -l /dev/uinput
adb shell getenforce
```
Pass: `uinput` in PATH, `/dev/uinput` exists, `id` includes uhid/equivalent, no SELinux denial.

**Phase B — Schema probe**: try symbolic registration JSON first; on failure, retry numeric
(constants documented in the full research artifact — see `virtual-gamepad/` module for the actual
implementation). Record `schema = symbolic | numeric | failed`.

**Phase C — Kernel/InputReader visibility**: `adb shell getevent -p` + `dumpsys input` while the
uinput process is alive; confirm device name appears with `EV_KEY`/`EV_ABS` capabilities and is
classified as gamepad/joystick/dpad.

**Phase D — Raw event echo test**: inject a single button down+up via `getevent -lt` observer,
confirm both edges appear with no write errors in logcat.

**Phase E — Emulator detection**: force-stop → launch → open controller/input settings → verify
device appears/binds (D-pad, A/B/X/Y, Start/Select, L1/R1, sticks) → save → restart → verify
mapping persisted.

**Phase F — Screenshot-diff functional test**: deterministic press sequence (Down/Up/A/B) against
a known menu, verify screenshot diffs match expected focus movement with no missed/double moves.

**Phase G — Rate stress test**: 20 D-pad presses at 250/125/60/33ms tiers; pick the fastest tier
with zero missed/double events, zero ANRs, zero stuck buttons as the production-safe rate for that
device+emulator combo.

**Phase H — Long-run soak** (10 min repeated menu-nav/toggle/back-out cycle): confirm no stuck
input, ANR, crash, or virtual-device disappearance under sustained use.

**Phase I — Per-run preflight gate** (before every actual benchmark run): confirm device still
visible in `dumpsys input`, send+confirm a single A press reacts, clear logcat, run benchmark, then
check `pidof`, grep logcat for ANR/InputDispatcher/uinput errors, and capture a final-state
screenshot.

## Final recommendation

Adopt `uinput` as the primary controller automation backend, with guardrails: per-device schema +
access probing, per-emulator binding validation before trusting results, one persistent session
(never per-button spawns), conservative menu timing, **USB ADB required for official runs** (Wi-Fi
only for dev/iteration), and never claim frame-perfect input without separate empirical measurement.
Treat it as a certified hardware abstraction, not a guaranteed platform invariant.
