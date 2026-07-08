#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from visual_analysis_lib import analyze_image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze screenshot resolution/color/sharpness characteristics."
    )
    parser.add_argument("image", help="Path to screenshot image (PNG/JPG).")
    parser.add_argument(
        "--device-info",
        dest="device_info",
        help="Optional path to device-info.json. If omitted, nearest ancestor device-info.json is used.",
    )
    parser.add_argument(
        "--out-json",
        dest="out_json",
        help="Optional JSON output path. JSON is still printed to stdout.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    image_path = Path(args.image)
    device_info_path = Path(args.device_info) if args.device_info else None
    report = analyze_image(image_path=image_path, device_info_path=device_info_path)

    payload = json.dumps(report, indent=2)
    print(payload)

    if args.out_json:
        out_path = Path(args.out_json)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

