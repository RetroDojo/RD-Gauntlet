#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

from visual_analysis_lib import analyze_image, fallback_ssim

try:
    from skimage.metrics import structural_similarity as skimage_ssim

    SKIMAGE_AVAILABLE = True
except Exception:
    skimage_ssim = None
    SKIMAGE_AVAILABLE = False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare two screenshots for structural/color/sharpness differences."
    )
    parser.add_argument("image_a", help="Reference screenshot path (A).")
    parser.add_argument("image_b", help="Comparison screenshot path (B).")
    parser.add_argument("--label-a", default="Image A")
    parser.add_argument("--label-b", default="Image B")
    parser.add_argument("--out-json", dest="out_json")
    parser.add_argument("--out-md", dest="out_md")
    return parser.parse_args()


def _to_gray_array(path: Path, target_size: tuple[int, int] | None = None) -> np.ndarray:
    with Image.open(path) as im:
        gray = im.convert("L")
        if target_size and gray.size != target_size:
            gray = gray.resize(target_size, Image.Resampling.LANCZOS)
        return np.asarray(gray, dtype=np.uint8)


def _ssim(gray_a: np.ndarray, gray_b: np.ndarray) -> tuple[float, str]:
    if SKIMAGE_AVAILABLE and skimage_ssim is not None:
        score = float(skimage_ssim(gray_a, gray_b, data_range=255))
        return round(score, 4), "scikit-image"
    return fallback_ssim(gray_a, gray_b), "manual-fallback-gaussian-window"


def _summary_lines(report: dict) -> str:
    blur_desc = report["humanSummary"]["blurDifference"]
    warmth_desc = report["humanSummary"]["warmthShift"]
    ssim = report["comparison"]["ssim"]["score"]
    method = report["comparison"]["ssim"]["method"]
    lines = [
        f"- SSIM: **{ssim}** ({method})",
        f"- {blur_desc}",
        f"- {warmth_desc}",
        "- Note: if dimensions differed, one image was resized before SSIM (approximation).",
        "- Raw screencap reflects final panel output; it cannot directly reveal internal emulator render resolution.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    path_a = Path(args.image_a).resolve()
    path_b = Path(args.image_b).resolve()

    report_a = analyze_image(path_a)
    report_b = analyze_image(path_b)

    target_size = (
        report_a["imageResolution"]["width"],
        report_a["imageResolution"]["height"],
    )
    gray_a = _to_gray_array(path_a, target_size=target_size)
    gray_b = _to_gray_array(path_b, target_size=target_size)

    ssim_score, ssim_method = _ssim(gray_a, gray_b)
    resized_for_ssim = (
        report_a["imageResolution"]["width"] != report_b["imageResolution"]["width"]
        or report_a["imageResolution"]["height"] != report_b["imageResolution"]["height"]
    )

    avg_a = report_a["colorSummary"]["averageRgb"]
    avg_b = report_b["colorSummary"]["averageRgb"]
    delta_rgb = {ch: round(avg_b[ch] - avg_a[ch], 4) for ch in ("r", "g", "b")}

    sharp_a = float(report_a["sharpness"]["score"])
    sharp_b = float(report_b["sharpness"]["score"])
    sharp_delta = round(sharp_b - sharp_a, 4)
    sharp_delta_pct = (
        round(((sharp_b - sharp_a) / sharp_a) * 100.0, 2) if abs(sharp_a) > 1e-9 else None
    )

    if sharp_delta_pct is None:
        blur_sentence = "Sharpness delta percent is unavailable because Image A sharpness is ~0."
    elif sharp_delta_pct < 0:
        blur_sentence = (
            f"{args.label_b} appears {abs(sharp_delta_pct):.2f}% blurrier "
            f"(lower Laplacian variance) than {args.label_a}."
        )
    elif sharp_delta_pct > 0:
        blur_sentence = (
            f"{args.label_b} appears {sharp_delta_pct:.2f}% sharper "
            f"(higher Laplacian variance) than {args.label_a}."
        )
    else:
        blur_sentence = "Both images have effectively identical Laplacian sharpness scores."

    warmth_value = round((delta_rgb["r"] - delta_rgb["b"]), 4)
    if warmth_value > 0:
        warmth_sentence = (
            f"{args.label_b} trends warmer than {args.label_a} (ΔR-ΔB = +{warmth_value:.4f})."
        )
    elif warmth_value < 0:
        warmth_sentence = (
            f"{args.label_b} trends cooler than {args.label_a} (ΔR-ΔB = {warmth_value:.4f})."
        )
    else:
        warmth_sentence = f"{args.label_b} and {args.label_a} have neutral red-vs-blue shift."

    report = {
        "analysisVersion": "1.0",
        "images": {
            "a": {
                "label": args.label_a,
                "path": str(path_a),
                "resolution": report_a["imageResolution"],
                "averageRgb": avg_a,
                "sharpnessScore": report_a["sharpness"]["score"],
            },
            "b": {
                "label": args.label_b,
                "path": str(path_b),
                "resolution": report_b["imageResolution"],
                "averageRgb": avg_b,
                "sharpnessScore": report_b["sharpness"]["score"],
            },
        },
        "comparison": {
            "ssim": {
                "score": ssim_score,
                "method": ssim_method,
                "grayscale": True,
                "resizedBeforeComparison": resized_for_ssim,
                "resizeReference": args.label_a,
                "resizeMethod": "Pillow LANCZOS",
            },
            "deltaAverageRgb_B_minus_A": delta_rgb,
            "deltaSharpness_B_minus_A": {
                "absolute": sharp_delta,
                "percentVsA": sharp_delta_pct,
            },
        },
        "humanSummary": {
            "blurDifference": blur_sentence,
            "warmthShift": warmth_sentence,
            "limitations": [
                "SSIM after resize is an approximation when source resolutions differ.",
                "Different scene timing/content can dominate metrics; true hardware comparison needs same game/emulator scene.",
                "Raw screencap reports final composed frame only, not internal emulator render resolution.",
            ],
        },
    }

    as_json = json.dumps(report, indent=2)
    print(as_json)

    if args.out_json:
        out_json = Path(args.out_json)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(as_json + "\n", encoding="utf-8")

    if args.out_md:
        out_md = Path(args.out_md)
        out_md.parent.mkdir(parents=True, exist_ok=True)
        md = (
            f"# Screenshot Comparison: {args.label_a} vs {args.label_b}\n\n"
            f"## Inputs\n\n"
            f"- {args.label_a}: `{path_a}`\n"
            f"- {args.label_b}: `{path_b}`\n\n"
            f"## Summary\n\n{_summary_lines(report)}\n"
        )
        out_md.write_text(md, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

