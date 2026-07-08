#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageFilter


def _safe_float(value: float) -> float:
    return round(float(value), 4)


def _read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _ratio_string(width: int, height: int) -> str:
    if width <= 0 or height <= 0:
        return "unknown"
    divisor = math.gcd(width, height)
    return f"{width // divisor}:{height // divisor}"


def _parse_wm_size(raw: str | None) -> tuple[int, int] | None:
    if not raw:
        return None
    match = re.search(r"(\d+)\s*x\s*(\d+)", raw)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def _find_nearest(path: Path, filename: str, max_levels: int = 5) -> Path | None:
    current = path.parent
    for _ in range(max_levels):
        candidate = current / filename
        if candidate.exists():
            return candidate
        if current.parent == current:
            break
        current = current.parent
    return None


def _find_device_info_path(image_path: Path) -> Path | None:
    return _find_nearest(image_path, "device-info.json")


def _channel_stats(rgb: np.ndarray, bins: int = 16) -> dict[str, Any]:
    channel_names = ("r", "g", "b")
    out: dict[str, Any] = {}
    for idx, name in enumerate(channel_names):
        channel = rgb[:, :, idx]
        hist, _ = np.histogram(channel, bins=bins, range=(0, 256))
        out[name] = {
            "mean": _safe_float(np.mean(channel)),
            "std": _safe_float(np.std(channel)),
            "histogram16": hist.astype(int).tolist(),
        }
    return out


def compute_laplacian_variance(gray_u8: np.ndarray) -> float:
    gray = gray_u8.astype(np.float32)
    if gray.shape[0] < 3 or gray.shape[1] < 3:
        return 0.0
    center = gray[1:-1, 1:-1]
    lap = (
        gray[:-2, 1:-1]
        + gray[2:, 1:-1]
        + gray[1:-1, :-2]
        + gray[1:-1, 2:]
        - (4.0 * center)
    )
    return _safe_float(np.var(lap))


def _banding_heuristic(rgb: np.ndarray) -> dict[str, Any]:
    total_pixels = int(rgb.shape[0] * rgb.shape[1])
    flat = rgb.reshape(-1, 3)
    sample_limit = 300_000
    step = max(1, flat.shape[0] // sample_limit)
    sampled = flat[::step]

    unique_colors = int(np.unique(sampled, axis=0).shape[0])
    unique_color_ratio = float(unique_colors / max(1, sampled.shape[0]))
    unique_values = {
        "r": int(np.unique(rgb[:, :, 0]).shape[0]),
        "g": int(np.unique(rgb[:, :, 1]).shape[0]),
        "b": int(np.unique(rgb[:, :, 2]).shape[0]),
    }
    suspicious_channels = [
        channel for channel, count in unique_values.items() if count <= 64
    ]
    likely_banding = (unique_color_ratio < 0.10) or bool(suspicious_channels)

    return {
        "totalPixels": total_pixels,
        "sampledPixelsForUniqueColorCount": int(sampled.shape[0]),
        "uniqueColorsInSample": unique_colors,
        "uniqueColorRatioInSample": _safe_float(unique_color_ratio),
        "uniqueValuesPerChannel": unique_values,
        "suspiciouslyLowDynamicChannels": suspicious_channels,
        "likelyBandingOrPosterization": likely_banding,
        "note": (
            "Heuristic only. Flat UI scenes or limited-palette content can look like "
            "banding even when color depth is normal."
        ),
    }


def analyze_image(
    image_path: Path, device_info_path: Path | None = None, histogram_bins: int = 16
) -> dict[str, Any]:
    image_path = image_path.resolve()
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    with Image.open(image_path) as im:
        rgb_img = im.convert("RGB")
        gray_img = rgb_img.convert("L")
        rgb = np.asarray(rgb_img, dtype=np.uint8)
        gray = np.asarray(gray_img, dtype=np.uint8)

    height, width = int(rgb.shape[0]), int(rgb.shape[1])
    panel_info: dict[str, Any] = {
        "deviceInfoPath": None,
        "productModel": None,
        "configuredName": None,
        "wmSizeRaw": None,
        "panelResolution": None,
        "screenshotMatchesPanelResolution": None,
        "matchType": "unknown",
    }

    if device_info_path is None:
        device_info_path = _find_device_info_path(image_path)

    if device_info_path:
        payload = _read_json(device_info_path)
        panel_info["deviceInfoPath"] = str(device_info_path)
        if payload:
            panel_info["productModel"] = payload.get("productModel")
            panel_info["configuredName"] = payload.get("configuredName")
            panel_info["wmSizeRaw"] = payload.get("wmSize")
            parsed = _parse_wm_size(payload.get("wmSize"))
            if parsed:
                panel_w, panel_h = parsed
                panel_info["panelResolution"] = {
                    "width": panel_w,
                    "height": panel_h,
                    "aspectRatio": _ratio_string(panel_w, panel_h),
                }
                if panel_w == width and panel_h == height:
                    panel_info["screenshotMatchesPanelResolution"] = True
                    panel_info["matchType"] = "exact"
                elif panel_w == height and panel_h == width:
                    panel_info["screenshotMatchesPanelResolution"] = True
                    panel_info["matchType"] = "orientation-swapped"
                else:
                    panel_info["screenshotMatchesPanelResolution"] = False
                    panel_info["matchType"] = "mismatch"

    mean_rgb = {
        "r": _safe_float(np.mean(rgb[:, :, 0])),
        "g": _safe_float(np.mean(rgb[:, :, 1])),
        "b": _safe_float(np.mean(rgb[:, :, 2])),
    }

    return {
        "analysisVersion": "1.0",
        "sourceImage": str(image_path),
        "imageResolution": {
            "width": width,
            "height": height,
            "aspectRatio": _ratio_string(width, height),
            "aspectRatioDecimal": _safe_float(width / max(1, height)),
            "pixelCount": width * height,
        },
        "deviceContext": panel_info,
        "colorSummary": {
            "averageRgb": mean_rgb,
            "channels": _channel_stats(rgb, bins=histogram_bins),
        },
        "sharpness": {
            "method": "Laplacian variance on grayscale",
            "kernel": [[0, 1, 0], [1, -4, 1], [0, 1, 0]],
            "score": compute_laplacian_variance(gray),
            "interpretation": "Higher values generally mean crisper edges; lower values can indicate blur.",
        },
        "bandingHeuristic": _banding_heuristic(rgb),
        "limitations": [
            "Raw Android screencap captures the final composited panel frame, not internal emulator render resolution.",
            "This analysis can describe final on-screen color/contrast/sharpness characteristics, but cannot prove internal upscaling filter type from screencap alone.",
        ],
    }


def _gaussian_blur_float_array(img: np.ndarray, radius: float = 1.5) -> np.ndarray:
    pil = Image.fromarray(img.astype(np.float32), mode="F")
    return np.asarray(pil.filter(ImageFilter.GaussianBlur(radius=radius)), dtype=np.float32)


def fallback_ssim(gray_a: np.ndarray, gray_b: np.ndarray) -> float:
    img1 = gray_a.astype(np.float32)
    img2 = gray_b.astype(np.float32)

    mu1 = _gaussian_blur_float_array(img1)
    mu2 = _gaussian_blur_float_array(img2)
    mu1_sq = mu1 * mu1
    mu2_sq = mu2 * mu2
    mu1_mu2 = mu1 * mu2

    sigma1_sq = _gaussian_blur_float_array(img1 * img1) - mu1_sq
    sigma2_sq = _gaussian_blur_float_array(img2 * img2) - mu2_sq
    sigma12 = _gaussian_blur_float_array(img1 * img2) - mu1_mu2

    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    numerator = (2 * mu1_mu2 + c1) * (2 * sigma12 + c2)
    denominator = (mu1_sq + mu2_sq + c1) * (sigma1_sq + sigma2_sq + c2)
    denominator = np.maximum(denominator, 1e-12)
    ssim_map = numerator / denominator
    return _safe_float(float(np.mean(ssim_map)))

