#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import rdg_virtual_gamepad as vg


def run_adb(serial: str, args: list[str], read_only: bool = True) -> subprocess.CompletedProcess:
    _ = read_only
    return subprocess.run(["adb", "-s", serial, *args], capture_output=True, text=True, check=False)


def print_step(label: str, ok: bool, detail: str) -> None:
    status = "PASS" if ok else "FAIL"
    print(f"[{label}] {status} - {detail}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pre-flight validator for new RetroDojo virtual gamepad devices."
    )
    parser.add_argument("--serial", help="ADB serial. If omitted and one device is present, it is used.")
    parser.add_argument("--profiles", default=str(vg.DEFAULT_PROFILES_PATH), help="Path to device profiles JSON.")
    parser.add_argument("--profile-id", help="Optional explicit profile id.")
    parser.add_argument(
        "--live",
        action="store_true",
        help="Enables live side-effecting checks (button injection). OFF by default.",
    )
    args = parser.parse_args()

    print("=== RD-Gauntlet Virtual Gamepad Pre-flight ===")
    print("READ-ONLY steps run always. SAFE-REGISTER steps only register/unregister. LIVE steps require --live.")

    try:
        serial = vg._resolve_target_serial(args.serial)
    except Exception as exc:
        print_step("READ-ONLY", False, f"ADB serial resolution failed: {exc}")
        return 1

    print_step("READ-ONLY", True, f"Using serial {serial}")
    product = vg.get_product_name(serial)
    print_step("READ-ONLY", True, f"Detected product: {product or '(unknown)'}")

    proc_help = run_adb(serial, ["shell", "uinput", "--help"], read_only=True)
    ok_help = proc_help.returncode == 0
    print_step("READ-ONLY", ok_help, "uinput --help reachable" if ok_help else (proc_help.stderr.strip() or proc_help.stdout.strip()))

    proc_getevent = run_adb(serial, ["shell", "getevent", "-p"], read_only=True)
    ok_getevent = proc_getevent.returncode == 0
    print_step("READ-ONLY", ok_getevent, "getevent -p readable" if ok_getevent else (proc_getevent.stderr.strip() or proc_getevent.stdout.strip()))

    profiles_doc = vg.load_profiles(Path(args.profiles))
    profile = vg.resolve_profile(profiles_doc, serial=serial, profile_id=args.profile_id, product_name=product)
    print_step("READ-ONLY", True, f"Resolved profile: {profile.profile_id} (schema={profile.schema})")

    try:
        schema_result = vg.probe_schema(serial, profile)
        print_step("SAFE-REGISTER", True, f"Detected schema={schema_result['schema']}")
    except Exception as exc:
        print_step("SAFE-REGISTER", False, f"Schema probe failed: {exc}")
        return 1

    if not args.live:
        print("[LIVE] SKIP - --live not provided (no button/axis injection performed).")
        print("Done.")
        return 0

    print("[LIVE] RUN - executing minimal round-trip button check (DPAD_DOWN).")
    try:
        with vg.open_session(serial, profile, schema_override=schema_result["schema"]) as session:
            session.press_button("DPAD_DOWN", hold_ms=60, inter_event_ms=120)
        print_step("LIVE", True, "Button injection round-trip completed.")
    except Exception as exc:
        print_step("LIVE", False, f"Live injection failed: {exc}")
        return 1

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

