#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


SYMBOLIC_TO_NUMERIC: Dict[str, str] = {
    "EV_SYN": "0",
    "EV_KEY": "1",
    "EV_ABS": "3",
    "SYN_REPORT": "0",
    "UI_SET_EVBIT": "100",
    "UI_SET_KEYBIT": "101",
    "UI_SET_ABSBIT": "103",
    "ABS_X": "0",
    "ABS_Y": "1",
    "ABS_Z": "2",
    "ABS_RZ": "5",
    "ABS_GAS": "9",
    "ABS_BRAKE": "10",
    "ABS_HAT0X": "16",
    "ABS_HAT0Y": "17",
    "BTN_SOUTH": "304",
    "BTN_EAST": "305",
    "BTN_NORTH": "307",
    "BTN_WEST": "308",
    "BTN_TL": "310",
    "BTN_TR": "311",
    "BTN_TL2": "312",
    "BTN_TR2": "313",
    "BTN_SELECT": "314",
    "BTN_START": "315",
    "BTN_MODE": "316",
    "BTN_THUMBL": "317",
    "BTN_THUMBR": "318",
    "BTN_DPAD_UP": "544",
    "BTN_DPAD_DOWN": "545",
    "BTN_DPAD_LEFT": "546",
    "BTN_DPAD_RIGHT": "547",
}

BUTTON_ALIASES: Dict[str, str] = {
    "A": "BTN_SOUTH",
    "B": "BTN_EAST",
    "X": "BTN_NORTH",
    "Y": "BTN_WEST",
    "L1": "BTN_TL",
    "R1": "BTN_TR",
    "L2": "BTN_TL2",
    "R2": "BTN_TR2",
    "SELECT": "BTN_SELECT",
    "BACK": "BTN_SELECT",
    "START": "BTN_START",
    "HOME": "BTN_MODE",
    "GUIDE": "BTN_MODE",
    "L3": "BTN_THUMBL",
    "R3": "BTN_THUMBR",
    "DPAD_UP": "BTN_DPAD_UP",
    "DPAD_DOWN": "BTN_DPAD_DOWN",
    "DPAD_LEFT": "BTN_DPAD_LEFT",
    "DPAD_RIGHT": "BTN_DPAD_RIGHT",
}

AXIS_ALIASES: Dict[str, str] = {
    "LX": "ABS_X",
    "LY": "ABS_Y",
    "RX": "ABS_Z",
    "RY": "ABS_RZ",
    "LT": "ABS_BRAKE",
    "RT": "ABS_GAS",
    "HATX": "ABS_HAT0X",
    "HATY": "ABS_HAT0Y",
}

DEFAULT_PROFILES_PATH = Path(__file__).resolve().parent / "device-profiles.json"

SCHEMA_HINT_ERROR_TOKENS = (
    "Encountered malformed data",
    "Invalid key in device configuration",
    "Error reading in object",
    "NumberFormatException",
    "For input string",
    "No enum constant",
)


def _hex_or_int(value: Any) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 0)
    raise TypeError(f"Expected int/str, got {type(value)}")


def _numeric_token(symbolic: str) -> str:
    if symbolic in SYMBOLIC_TO_NUMERIC:
        return SYMBOLIC_TO_NUMERIC[symbolic]
    raise KeyError(f"No numeric mapping for token: {symbolic}")


def _normalized_button_name(name: str) -> str:
    token = name.strip().upper()
    token = BUTTON_ALIASES.get(token, token)
    if token not in SYMBOLIC_TO_NUMERIC:
        raise ValueError(f"Unsupported button '{name}'.")
    return token


def _normalized_axis_name(name: str) -> str:
    token = name.strip().upper()
    token = AXIS_ALIASES.get(token, token)
    if token not in ("ABS_X", "ABS_Y", "ABS_Z", "ABS_RZ", "ABS_GAS", "ABS_BRAKE", "ABS_HAT0X", "ABS_HAT0Y"):
        raise ValueError(f"Unsupported axis '{name}'.")
    return token


def _axis_value_to_evdev(axis: str, normalized: float) -> int:
    if axis in ("ABS_GAS", "ABS_BRAKE"):
        clamped = max(0.0, min(1.0, normalized))
        return int(round(clamped * 32767))
    if axis in ("ABS_HAT0X", "ABS_HAT0Y"):
        if normalized <= -0.5:
            return -1
        if normalized >= 0.5:
            return 1
        return 0
    clamped = max(-1.0, min(1.0, normalized))
    return int(round(clamped * 32767))


def _convert_obj_to_numeric(obj: Any) -> Any:
    if isinstance(obj, list):
        return [_convert_obj_to_numeric(item) for item in obj]
    if isinstance(obj, dict):
        converted: Dict[str, Any] = {}
        for key, value in obj.items():
            if key in ("type", "code"):
                if isinstance(value, str) and value in SYMBOLIC_TO_NUMERIC:
                    converted[key] = _numeric_token(value)
                else:
                    converted[key] = str(_hex_or_int(value))
            elif key in ("vid", "pid", "id", "duration", "value", "minimum", "maximum", "fuzz", "flat", "resolution", "ff_effects_max"):
                converted[key] = str(_hex_or_int(value))
            elif key in ("events", "data"):
                out = []
                for item in value:
                    if isinstance(item, str) and item in SYMBOLIC_TO_NUMERIC:
                        out.append(_numeric_token(item))
                    elif isinstance(item, int):
                        out.append(str(item))
                    elif isinstance(item, str) and item.strip():
                        try:
                            out.append(str(_hex_or_int(item)))
                        except Exception:
                            out.append(item)
                    else:
                        out.append(item)
                converted[key] = out
            else:
                converted[key] = _convert_obj_to_numeric(value)
        return converted
    if isinstance(obj, int):
        return str(obj)
    return obj


@dataclass
class DeviceProfile:
    profile_id: str
    serial: Optional[str]
    product_name: Optional[str]
    vid: int
    pid: int
    schema: str
    bus: str = "usb"
    display_name: str = "RDG Virtual Pad"
    default_hold_ms: int = 90
    default_inter_event_ms: int = 60
    startup_delay_ms: int = 120
    abs_flat: int = 15
    quirks: Dict[str, Any] = field(default_factory=dict)


def load_profiles(path: Path) -> Dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if "profiles" not in data or not isinstance(data["profiles"], list):
        raise ValueError(f"Invalid profiles file: {path}")
    return data


def resolve_profile(profiles_doc: Dict[str, Any], *, serial: Optional[str], profile_id: Optional[str], product_name: Optional[str]) -> DeviceProfile:
    defaults = profiles_doc.get("defaults", {})
    selected: Optional[Dict[str, Any]] = None
    if profile_id:
        selected = next((entry for entry in profiles_doc["profiles"] if entry.get("id") == profile_id), None)
    if selected is None and serial:
        selected = next((entry for entry in profiles_doc["profiles"] if (entry.get("match", {}).get("serial") or "").lower() == serial.lower()), None)
    if selected is None and product_name:
        selected = next((entry for entry in profiles_doc["profiles"] if (entry.get("match", {}).get("product_name") or "").lower() == product_name.lower()), None)
    if selected is None:
        selected = profiles_doc.get("fallback")
        if not selected:
            raise ValueError("No matching device profile found and no fallback profile is configured.")

    merged = {}
    merged.update(defaults)
    merged.update(selected)
    match = merged.get("match", {})
    quirks = dict(defaults.get("quirks", {}))
    quirks.update(merged.get("quirks", {}))
    return DeviceProfile(
        profile_id=merged["id"],
        serial=match.get("serial"),
        product_name=match.get("product_name"),
        vid=_hex_or_int(merged["vid"]),
        pid=_hex_or_int(merged["pid"]),
        schema=(merged.get("schema") or "auto").lower(),
        bus=(merged.get("bus") or "usb").lower(),
        display_name=merged.get("display_name") or "RDG Virtual Pad",
        default_hold_ms=int(quirks.get("default_hold_ms", 90)),
        default_inter_event_ms=int(quirks.get("default_inter_event_ms", 60)),
        startup_delay_ms=int(quirks.get("startup_delay_ms", 120)),
        abs_flat=int(quirks.get("abs_flat", 15)),
        quirks=quirks,
    )


def list_connected_devices() -> List[str]:
    proc = subprocess.run(["adb", "devices"], capture_output=True, text=True, check=False)
    lines = proc.stdout.splitlines()
    devices = []
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    return devices


def get_product_name(serial: str) -> str:
    proc = subprocess.run(["adb", "-s", serial, "shell", "getprop", "ro.product.model"], capture_output=True, text=True, check=False)
    return proc.stdout.strip()


def run_uinput_oneshot(serial: str, events: Iterable[Dict[str, Any]]) -> subprocess.CompletedProcess:
    payload = "\n".join(json.dumps(event, separators=(",", ":")) for event in events) + "\n"
    return subprocess.run(
        ["adb", "-s", serial, "shell", "uinput", "-"],
        input=payload,
        capture_output=True,
        text=True,
        check=False,
    )


def _build_probe_register(profile: DeviceProfile, schema: str, probe_id: int) -> Dict[str, Any]:
    register = {
        "id": probe_id,
        "command": "register",
        "name": f"{profile.display_name} Probe",
        "vid": profile.vid,
        "pid": profile.pid,
        "bus": profile.bus,
        "configuration": [
            {"type": "UI_SET_EVBIT", "data": ["EV_KEY"]},
            {"type": "UI_SET_KEYBIT", "data": ["BTN_SOUTH"]},
        ],
    }
    if schema == "numeric":
        return _convert_obj_to_numeric(register)
    return register


def probe_schema(serial: str, profile: DeviceProfile) -> Dict[str, Any]:
    # NOTE: deliberately do NOT send a "sync" command here. "sync" was only added in
    # Android 15/mainline's uinput tool; on older (Android 13/14-era) builds it is an
    # unrecognized command that makes the whole process exit non-zero even though
    # registration itself succeeded cleanly. Schema success/failure must be judged from
    # the presence/absence of parse-error text, not the process return code, since a
    # register-only session on a healthy device also exits non-zero on some builds simply
    # because stdin closes without an explicit "unregister" (this is normal/expected).
    for schema in ("symbolic", "numeric"):
        register = _build_probe_register(profile, schema, probe_id=99)
        proc = run_uinput_oneshot(serial, [register])
        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        has_schema_error = any(marker in combined for marker in SCHEMA_HINT_ERROR_TOKENS)
        success = not has_schema_error
        if success:
            return {
                "schema": schema,
                "return_code": proc.returncode,
                "stdout": proc.stdout.strip(),
                "stderr": proc.stderr.strip(),
            }
    raise RuntimeError("Unable to determine uinput schema. Configure schema explicitly in device profile.")


class VirtualGamepadSession:
    def __init__(self, serial: str, profile: DeviceProfile, schema: str):
        self.serial = serial
        self.profile = profile
        self.schema = schema
        self.device_id = 1
        self._proc: Optional[subprocess.Popen[str]] = None

    def __enter__(self) -> "VirtualGamepadSession":
        self.open()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _convert_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        if self.schema == "numeric":
            return _convert_obj_to_numeric(event)
        return event

    def open(self) -> None:
        self._proc = subprocess.Popen(
            ["adb", "-s", self.serial, "shell", "uinput", "-"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        register = self._build_register_event()
        self.send_event(register)
        if self.profile.startup_delay_ms > 0:
            time.sleep(self.profile.startup_delay_ms / 1000.0)

    def close(self) -> None:
        if self._proc is None:
            return
        try:
            if self._proc.stdin and not self._proc.stdin.closed:
                self._proc.stdin.close()
        finally:
            try:
                self._proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                self._proc.wait(timeout=2.0)
            self._proc = None

    def send_event(self, event: Dict[str, Any]) -> None:
        if self._proc is None or self._proc.stdin is None:
            raise RuntimeError("Session is not open.")
        payload = json.dumps(self._convert_event(event), separators=(",", ":")) + "\n"
        self._proc.stdin.write(payload)
        self._proc.stdin.flush()

    def _build_register_event(self) -> Dict[str, Any]:
        return {
            "id": self.device_id,
            "command": "register",
            "name": self.profile.display_name,
            "vid": self.profile.vid,
            "pid": self.profile.pid,
            "bus": self.profile.bus,
            "configuration": [
                {"type": "UI_SET_EVBIT", "data": ["EV_KEY", "EV_ABS"]},
                {
                    "type": "UI_SET_KEYBIT",
                    "data": [
                        "BTN_SOUTH",
                        "BTN_EAST",
                        "BTN_NORTH",
                        "BTN_WEST",
                        "BTN_TL",
                        "BTN_TR",
                        "BTN_TL2",
                        "BTN_TR2",
                        "BTN_SELECT",
                        "BTN_START",
                        "BTN_MODE",
                        "BTN_THUMBL",
                        "BTN_THUMBR",
                        "BTN_DPAD_UP",
                        "BTN_DPAD_DOWN",
                        "BTN_DPAD_LEFT",
                        "BTN_DPAD_RIGHT",
                    ],
                },
                {"type": "UI_SET_ABSBIT", "data": ["ABS_X", "ABS_Y", "ABS_Z", "ABS_RZ", "ABS_GAS", "ABS_BRAKE", "ABS_HAT0X", "ABS_HAT0Y"]},
            ],
            "abs_info": [
                {"code": "ABS_X", "info": {"value": 0, "minimum": -32767, "maximum": 32767, "fuzz": 0, "flat": self.profile.abs_flat, "resolution": 0}},
                {"code": "ABS_Y", "info": {"value": 0, "minimum": -32767, "maximum": 32767, "fuzz": 0, "flat": self.profile.abs_flat, "resolution": 0}},
                {"code": "ABS_Z", "info": {"value": 0, "minimum": -32767, "maximum": 32767, "fuzz": 0, "flat": self.profile.abs_flat, "resolution": 0}},
                {"code": "ABS_RZ", "info": {"value": 0, "minimum": -32767, "maximum": 32767, "fuzz": 0, "flat": self.profile.abs_flat, "resolution": 0}},
                {"code": "ABS_GAS", "info": {"value": 0, "minimum": 0, "maximum": 32767, "fuzz": 0, "flat": 0, "resolution": 0}},
                {"code": "ABS_BRAKE", "info": {"value": 0, "minimum": 0, "maximum": 32767, "fuzz": 0, "flat": 0, "resolution": 0}},
                {"code": "ABS_HAT0X", "info": {"value": 0, "minimum": -1, "maximum": 1, "fuzz": 0, "flat": 0, "resolution": 0}},
                {"code": "ABS_HAT0Y", "info": {"value": 0, "minimum": -1, "maximum": 1, "fuzz": 0, "flat": 0, "resolution": 0}},
            ],
        }

    def inject_triplets(self, triplets: List[Any]) -> None:
        self.send_event({"id": self.device_id, "command": "inject", "events": triplets})

    def press_button(self, button: str, hold_ms: int, inter_event_ms: int) -> None:
        code = _normalized_button_name(button)
        events = [
            "EV_KEY",
            code,
            1,
            "EV_SYN",
            "SYN_REPORT",
            0,
        ]
        self.inject_triplets(events)
        if hold_ms > 0:
            time.sleep(hold_ms / 1000.0)
        self.inject_triplets(["EV_KEY", code, 0, "EV_SYN", "SYN_REPORT", 0])
        if inter_event_ms > 0:
            time.sleep(inter_event_ms / 1000.0)

    def set_axis(self, axis: str, value: float, inter_event_ms: int) -> None:
        axis_token = _normalized_axis_name(axis)
        evdev_value = _axis_value_to_evdev(axis_token, value)
        self.inject_triplets(["EV_ABS", axis_token, evdev_value, "EV_SYN", "SYN_REPORT", 0])
        if inter_event_ms > 0:
            time.sleep(inter_event_ms / 1000.0)

    def press_sequence(self, steps: List[Dict[str, Any]], hold_ms: int, inter_event_ms: int) -> None:
        for step in steps:
            action = (step.get("action") or "").lower()
            if action == "button":
                self.press_button(
                    button=step["button"],
                    hold_ms=int(step.get("hold_ms", hold_ms)),
                    inter_event_ms=int(step.get("inter_event_ms", inter_event_ms)),
                )
            elif action == "axis":
                self.set_axis(
                    axis=step["axis"],
                    value=float(step["value"]),
                    inter_event_ms=int(step.get("inter_event_ms", inter_event_ms)),
                )
            elif action == "delay":
                time.sleep(max(0, int(step.get("duration_ms", 0))) / 1000.0)
            else:
                raise ValueError(f"Unknown sequence action '{action}'.")


def open_session(serial: str, profile: DeviceProfile, schema_override: Optional[str]) -> VirtualGamepadSession:
    schema = (schema_override or profile.schema).lower()
    if schema == "auto":
        schema = probe_schema(serial, profile)["schema"]
    if schema not in ("symbolic", "numeric"):
        raise ValueError("Schema must be symbolic, numeric, or auto.")
    return VirtualGamepadSession(serial=serial, profile=profile, schema=schema)


def _build_common_parser() -> argparse.ArgumentParser:
    # add_help=False: this is used as a `parents=[...]` mix-in for both the top-level
    # parser and every subcommand parser (see build_parser), so --serial/--profile-id/
    # --profiles/--schema can be passed either before or after the subcommand name.
    # Without add_help=False here, argparse raises a conflicting-option error for -h/--help
    # being defined twice once this parser is used as a parent for the top-level parser
    # (which needs its own real --help).
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--serial", help="ADB serial. If omitted and exactly one device is attached, that device is used.")
    parser.add_argument("--profile-id", help="Profile id from device-profiles.json.")
    parser.add_argument("--profiles", default=str(DEFAULT_PROFILES_PATH), help="Path to device-profiles.json.")
    parser.add_argument("--schema", choices=["auto", "symbolic", "numeric"], help="Override schema.")
    return parser


def _resolve_target_serial(cli_serial: Optional[str]) -> str:
    if cli_serial:
        return cli_serial
    devices = list_connected_devices()
    if len(devices) == 1:
        return devices[0]
    if not devices:
        raise RuntimeError("No adb device is connected.")
    raise RuntimeError("Multiple adb devices connected; pass --serial.")


def _load_context(args: argparse.Namespace) -> tuple[str, DeviceProfile]:
    serial = _resolve_target_serial(args.serial)
    profiles_doc = load_profiles(Path(args.profiles))
    product_name = get_product_name(serial)
    profile = resolve_profile(
        profiles_doc,
        serial=serial,
        profile_id=args.profile_id,
        product_name=product_name,
    )
    return serial, profile


def cmd_probe_schema(args: argparse.Namespace) -> int:
    serial, profile = _load_context(args)
    result = probe_schema(serial, profile)
    print(json.dumps({"serial": serial, "profile_id": profile.profile_id, **result}, indent=2))
    return 0


def cmd_register(args: argparse.Namespace) -> int:
    serial, profile = _load_context(args)
    keep_alive_ms = max(0, int(args.keep_alive_ms))
    with open_session(serial, profile, args.schema):
        if keep_alive_ms > 0:
            time.sleep(keep_alive_ms / 1000.0)
    print(f"Registered and cleaned up virtual gamepad for {serial}.")
    return 0


def cmd_press_button(args: argparse.Namespace) -> int:
    serial, profile = _load_context(args)
    hold_ms = int(args.hold_ms if args.hold_ms is not None else profile.default_hold_ms)
    inter_event_ms = int(args.inter_event_ms if args.inter_event_ms is not None else profile.default_inter_event_ms)
    with open_session(serial, profile, args.schema) as session:
        session.press_button(args.button, hold_ms=hold_ms, inter_event_ms=inter_event_ms)
    print(f"Pressed {args.button} on {serial} and cleaned up.")
    return 0


def cmd_set_axis(args: argparse.Namespace) -> int:
    serial, profile = _load_context(args)
    inter_event_ms = int(args.inter_event_ms if args.inter_event_ms is not None else profile.default_inter_event_ms)
    with open_session(serial, profile, args.schema) as session:
        session.set_axis(args.axis, value=float(args.value), inter_event_ms=inter_event_ms)
    print(f"Set axis {args.axis}={args.value} on {serial} and cleaned up.")
    return 0


def cmd_press_sequence(args: argparse.Namespace) -> int:
    serial, profile = _load_context(args)
    hold_ms = int(args.hold_ms if args.hold_ms is not None else profile.default_hold_ms)
    inter_event_ms = int(args.inter_event_ms if args.inter_event_ms is not None else profile.default_inter_event_ms)
    steps = json.loads(Path(args.sequence_file).read_text(encoding="utf-8"))
    if not isinstance(steps, list):
        raise ValueError("Sequence file must contain a JSON array.")
    with open_session(serial, profile, args.schema) as session:
        session.press_sequence(steps=steps, hold_ms=hold_ms, inter_event_ms=inter_event_ms)
    print(f"Executed sequence from {args.sequence_file} on {serial} and cleaned up.")
    return 0


def cmd_unregister(args: argparse.Namespace) -> int:
    _ = args
    print("No persistent daemon session is used. Cleanup happens automatically on stdin close / context exit.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    shared = _build_common_parser()
    parser = argparse.ArgumentParser(
        description="RetroDojo virtual gamepad automation via adb shell uinput.",
        parents=[shared],
    )
    sub = parser.add_subparsers(dest="command", required=True)

    probe = sub.add_parser("probe-schema", help="Probe symbolic vs numeric uinput schema.", parents=[shared])
    probe.set_defaults(func=cmd_probe_schema)

    register = sub.add_parser("register-gamepad", help="Register gamepad and keep it alive briefly.", parents=[shared])
    register.add_argument("--keep-alive-ms", default="800", help="How long to keep session open before cleanup.")
    register.set_defaults(func=cmd_register)

    press_button = sub.add_parser("press-button", help="Press one button in an auto-cleanup session.", parents=[shared])
    press_button.add_argument("button", help="Button name or alias (A/B/X/Y/L1/R1/etc).")
    press_button.add_argument("--hold-ms", type=int, help="Button hold duration.")
    press_button.add_argument("--inter-event-ms", type=int, help="Inter-event delay after release.")
    press_button.set_defaults(func=cmd_press_button)

    press_sequence = sub.add_parser("press-sequence", help="Execute a JSON button/axis/delay sequence.", parents=[shared])
    press_sequence.add_argument("--sequence-file", required=True, help="Path to sequence JSON.")
    press_sequence.add_argument("--hold-ms", type=int, help="Default hold duration for button steps.")
    press_sequence.add_argument("--inter-event-ms", type=int, help="Default inter-event delay.")
    press_sequence.set_defaults(func=cmd_press_sequence)

    set_axis = sub.add_parser("set-axis", help="Set one axis value in an auto-cleanup session.", parents=[shared])
    set_axis.add_argument("axis", help="Axis (LX,LY,RX,RY,LT,RT,HATX,HATY or ABS_*).")
    set_axis.add_argument("value", type=float, help="Normalized axis value.")
    set_axis.add_argument("--inter-event-ms", type=int, help="Inter-event delay.")
    set_axis.set_defaults(func=cmd_set_axis)

    unregister = sub.add_parser("unregister", help="Documented no-op for stateless CLI sessions.", parents=[shared])
    unregister.set_defaults(func=cmd_unregister)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

