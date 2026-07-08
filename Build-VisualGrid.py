#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from PIL import Image


def _safe_float(value: float, digits: int = 3) -> float:
    return round(float(value), digits)


def _ratio_string(width: int, height: int) -> str:
    if width <= 0 or height <= 0:
        return "unknown"
    divisor = math.gcd(width, height)
    return f"{width // divisor}:{height // divisor}"


def _normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def _load_json(path: Path) -> Any | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _parse_wm_size(raw: str | None) -> tuple[int, int] | None:
    if not raw:
        return None
    match = re.search(r"(\d+)\s*x\s*(\d+)", raw)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


@dataclass
class CaptureRecord:
    app: str
    shot_name: str
    image_path: Path
    run_name: str
    configured_name: str | None
    product_model: str | None
    screenshot_width: int
    screenshot_height: int
    screenshot_aspect: str
    panel_width: int | None
    panel_height: int | None
    panel_diagonal: float | None
    panel_ppi: float | None
    panel_name: str | None
    spec_match_type: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a static HTML gallery that compares real captured screenshots "
            "across devices and runs."
        )
    )
    parser.add_argument(
        "results_roots",
        nargs="+",
        help=(
            "One or more run directories (results/<run-name>) or parent folders "
            "that contain run directories."
        ),
    )
    parser.add_argument(
        "--out-html",
        dest="out_html",
        required=True,
        help="Output path for generated HTML gallery.",
    )
    parser.add_argument(
        "--app-filter",
        dest="app_filters",
        action="append",
        default=[],
        help=(
            "Optional case-insensitive app filter. Can be repeated. "
            "Example: --app-filter RetroArch --app-filter DraStic"
        ),
    )
    return parser.parse_args()


def _load_device_specs(base_dir: Path) -> list[dict[str, Any]]:
    device_specs_path = base_dir / "device-specs.json"
    payload = _load_json(device_specs_path)
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def _ppi(panel_width: int, panel_height: int, diagonal_inches: float) -> float | None:
    if panel_width <= 0 or panel_height <= 0 or diagonal_inches <= 0:
        return None
    return _safe_float(math.hypot(panel_width, panel_height) / diagonal_inches, 2)


def _build_spec_index(specs: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    index: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for spec in specs:
        for raw in (spec.get("id"), spec.get("name")):
            if isinstance(raw, str):
                index[_normalize_key(raw)].append(spec)
    return index


def _match_device_spec(
    spec_index: dict[str, list[dict[str, Any]]],
    specs: list[dict[str, Any]],
    configured_name: str | None,
    run_name: str,
    wm_size: tuple[int, int] | None,
) -> tuple[dict[str, Any] | None, str]:
    candidate_keys: list[str] = []
    if configured_name:
        candidate_keys.append(_normalize_key(configured_name))
    candidate_keys.append(_normalize_key(run_name))

    for key in candidate_keys:
        if not key:
            continue
        direct = spec_index.get(key)
        if direct:
            return direct[0], "direct-key"

    for key in candidate_keys:
        if not key:
            continue
        for spec in specs:
            id_key = _normalize_key(str(spec.get("id", "")))
            name_key = _normalize_key(str(spec.get("name", "")))
            if key and ((key in id_key) or (key in name_key) or (id_key and id_key in key)):
                return spec, "fuzzy-key"

    if wm_size:
        matches = []
        wm_w, wm_h = wm_size
        for spec in specs:
            pw = spec.get("panelWidth")
            ph = spec.get("panelHeight")
            if not isinstance(pw, int) or not isinstance(ph, int):
                continue
            if (pw == wm_w and ph == wm_h) or (pw == wm_h and ph == wm_w):
                matches.append(spec)
        if len(matches) == 1:
            return matches[0], "wm-size"
    return None, "none"


def _resolve_image_src(image_path: Path, output_html: Path) -> str:
    out_dir = output_html.parent.resolve()
    image_resolved = image_path.resolve()
    try:
        relative = os.path.relpath(str(image_resolved), str(out_dir))
        return Path(relative).as_posix()
    except ValueError:
        return image_resolved.as_uri()


def _scan_run_dir(
    run_dir: Path,
    app_filters: list[str],
    specs: list[dict[str, Any]],
    spec_index: dict[str, list[dict[str, Any]]],
) -> list[CaptureRecord]:
    captures: list[CaptureRecord] = []
    run_name = run_dir.name
    device_info = _load_json(run_dir / "device-info.json")
    if not isinstance(device_info, dict):
        device_info = {}

    configured_name = device_info.get("configuredName")
    configured_name = configured_name if isinstance(configured_name, str) else None
    product_model = device_info.get("productModel")
    product_model = product_model if isinstance(product_model, str) else None
    wm_size = _parse_wm_size(device_info.get("wmSize"))
    spec, spec_match_type = _match_device_spec(
        spec_index=spec_index,
        specs=specs,
        configured_name=configured_name,
        run_name=run_name,
        wm_size=wm_size,
    )

    for app_dir in sorted([p for p in run_dir.iterdir() if p.is_dir()], key=lambda p: p.name.lower()):
        pngs = sorted(app_dir.glob("*.png"), key=lambda p: p.name.lower())
        if not pngs:
            continue

        app_metadata = _load_json(app_dir / "app-metadata.json")
        app_name = app_dir.name
        if isinstance(app_metadata, dict) and isinstance(app_metadata.get("name"), str):
            app_name = app_metadata["name"]

        if app_filters:
            if not any(f.lower() in app_name.lower() for f in app_filters):
                continue

        for png_path in pngs:
            with Image.open(png_path) as image:
                width, height = image.size
            panel_width = spec.get("panelWidth") if isinstance(spec, dict) else None
            panel_height = spec.get("panelHeight") if isinstance(spec, dict) else None
            panel_diagonal = spec.get("diagonalInches") if isinstance(spec, dict) else None
            panel_name = spec.get("name") if isinstance(spec, dict) else configured_name

            if not isinstance(panel_width, int) and wm_size:
                panel_width = wm_size[0]
            if not isinstance(panel_height, int) and wm_size:
                panel_height = wm_size[1]
            if not isinstance(panel_diagonal, (int, float)):
                panel_diagonal = None

            panel_ppi = None
            if isinstance(panel_width, int) and isinstance(panel_height, int) and panel_diagonal:
                panel_ppi = _ppi(panel_width, panel_height, float(panel_diagonal))

            captures.append(
                CaptureRecord(
                    app=app_name,
                    shot_name=png_path.name,
                    image_path=png_path,
                    run_name=run_name,
                    configured_name=configured_name,
                    product_model=product_model,
                    screenshot_width=width,
                    screenshot_height=height,
                    screenshot_aspect=_ratio_string(width, height),
                    panel_width=panel_width if isinstance(panel_width, int) else None,
                    panel_height=panel_height if isinstance(panel_height, int) else None,
                    panel_diagonal=float(panel_diagonal) if isinstance(panel_diagonal, (int, float)) else None,
                    panel_ppi=panel_ppi,
                    panel_name=panel_name if isinstance(panel_name, str) else None,
                    spec_match_type=spec_match_type,
                )
            )
    return captures


def _expand_run_dirs(input_roots: list[Path]) -> list[Path]:
    run_dirs: list[Path] = []
    for root in input_roots:
        if not root.exists() or not root.is_dir():
            continue

        if any(root.glob("*/*.png")):
            run_dirs.append(root)
            continue

        for child in sorted([p for p in root.iterdir() if p.is_dir()], key=lambda p: p.name.lower()):
            if any(child.glob("*/*.png")):
                run_dirs.append(child)
    deduped: list[Path] = []
    seen: set[str] = set()
    for path in run_dirs:
        key = str(path.resolve()).lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(path)
    return deduped


def _format_panel_line(record: CaptureRecord) -> str:
    parts: list[str] = []
    if record.panel_name:
        parts.append(record.panel_name)
    if record.panel_width and record.panel_height:
        parts.append(f"{record.panel_width}x{record.panel_height}")
    if record.panel_diagonal:
        parts.append(f'{record.panel_diagonal:.2f}"')
    if record.panel_ppi:
        parts.append(f"{record.panel_ppi:.2f} PPI")
    if not parts:
        return "Panel spec unavailable"
    return " | ".join(parts)


def _build_html(records: list[CaptureRecord], output_html: Path) -> str:
    grouped: dict[str, dict[str, list[CaptureRecord]]] = defaultdict(lambda: defaultdict(list))
    for record in records:
        grouped[record.app][record.shot_name].append(record)

    app_names = sorted(grouped.keys(), key=lambda value: value.lower())
    total_images = len(records)
    generated = datetime.now().isoformat(timespec="seconds")
    html_parts: list[str] = []

    html_parts.append(
        """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RetroDojo Real-Capture Visual Grid</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #0f1116; color: #e7edf5; font-family: Segoe UI, Arial, sans-serif; }
  .wrap { max-width: 1600px; margin: 0 auto; padding: 16px 20px 30px; }
  .summary { padding: 12px; border: 1px solid #2a3342; border-radius: 8px; background: #141925; margin-bottom: 16px; }
  .summary code { color: #9ecbff; }
  .controls { margin: 8px 0 20px; display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
  .app { margin-bottom: 26px; }
  .app h2 { margin: 0 0 10px; color: #9ecbff; }
  .shot h3 { margin: 14px 0 10px; color: #bed6ff; font-size: 1rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 12px; }
  .card { border: 1px solid #2a3342; border-radius: 10px; background: #121826; overflow: hidden; }
  .card-head { padding: 10px; border-bottom: 1px solid #263041; font-size: 0.92rem; line-height: 1.35; }
  .card-head .run { color: #8fb4f0; }
  .card-head .panel { color: #d2d9e2; }
  .image-wrap { position: relative; background: #06080d; display: grid; place-items: center; min-height: 180px; }
  img { display: block; width: 100%; height: auto; image-rendering: auto; }
  .meta-overlay {
    position: absolute; left: 8px; bottom: 8px; right: 8px;
    background: rgba(0, 0, 0, 0.68); border: 1px solid rgba(255,255,255,0.15);
    padding: 6px 8px; font-size: 0.82rem; border-radius: 6px;
  }
  body.hide-meta .meta-overlay { display: none; }
  .small { opacity: 0.86; font-size: 0.82rem; }
</style>
</head>
<body class="show-meta">
<div class="wrap">
<h1>RetroDojo Real-Capture Visual Grid</h1>
"""
    )

    html_parts.append(
        (
            '<div class="summary">'
            f"<div><strong>Generated:</strong> {html.escape(generated)}</div>"
            f"<div><strong>Apps:</strong> {len(app_names)} | <strong>Images:</strong> {total_images}</div>"
            "<div class='small'>Shows real captured screenshots from run folders; this is not synthetic scaling math.</div>"
            "</div>"
        )
    )
    html_parts.append(
        """
<div class="controls">
  <label><input id="metaToggle" type="checkbox" checked> Show pixel/aspect overlay</label>
</div>
"""
    )

    if not app_names:
        html_parts.append("<p>No screenshots matched your inputs.</p>")
    else:
        for app in app_names:
            html_parts.append(f'<section class="app"><h2>{html.escape(app)}</h2>')
            for shot_name in sorted(grouped[app].keys(), key=lambda value: value.lower()):
                items = sorted(
                    grouped[app][shot_name],
                    key=lambda item: (
                        (item.configured_name or "").lower(),
                        item.run_name.lower(),
                        item.image_path.as_posix().lower(),
                    ),
                )
                html_parts.append(f'<div class="shot"><h3>{html.escape(shot_name)}</h3><div class="grid">')
                for item in items:
                    src = _resolve_image_src(item.image_path, output_html)
                    identity = item.configured_name or item.panel_name or "Unknown device"
                    panel_line = _format_panel_line(item)
                    overlay = (
                        f"{item.screenshot_width}x{item.screenshot_height} "
                        f"({item.screenshot_aspect}) | spec-match: {item.spec_match_type}"
                    )
                    html_parts.append(
                        (
                            '<article class="card">'
                            '<div class="card-head">'
                            f"<div><strong>{html.escape(identity)}</strong></div>"
                            f'<div class="run">Run: {html.escape(item.run_name)}</div>'
                            f'<div class="panel">{html.escape(panel_line)}</div>'
                            "</div>"
                            '<div class="image-wrap">'
                            f'<img src="{html.escape(src)}" alt="{html.escape(app)} {html.escape(shot_name)} {html.escape(identity)}">'
                            f'<div class="meta-overlay">{html.escape(overlay)}</div>'
                            "</div>"
                            "</article>"
                        )
                    )
                html_parts.append("</div></div>")
            html_parts.append("</section>")

    html_parts.append(
        """
</div>
<script>
  const toggle = document.getElementById('metaToggle');
  toggle.addEventListener('change', () => {
    document.body.classList.toggle('hide-meta', !toggle.checked);
  });
</script>
</body>
</html>
"""
    )
    return "\n".join(html_parts)


def main() -> int:
    args = parse_args()
    suite_dir = Path(__file__).resolve().parent
    out_html = Path(args.out_html).resolve()
    out_html.parent.mkdir(parents=True, exist_ok=True)

    specs = _load_device_specs(suite_dir)
    spec_index = _build_spec_index(specs)
    input_roots = [Path(root).resolve() for root in args.results_roots]
    run_dirs = _expand_run_dirs(input_roots)
    if not run_dirs:
        raise SystemExit("No run directories containing PNG screenshots were found.")

    records: list[CaptureRecord] = []
    for run_dir in run_dirs:
        records.extend(
            _scan_run_dir(
                run_dir=run_dir,
                app_filters=args.app_filters,
                specs=specs,
                spec_index=spec_index,
            )
        )

    html_payload = _build_html(records, out_html)
    out_html.write_text(html_payload, encoding="utf-8")

    summary = {
        "outputHtml": str(out_html),
        "runDirectories": [str(path) for path in run_dirs],
        "appFilter": args.app_filters,
        "totalCaptures": len(records),
        "totalApps": len({record.app for record in records}),
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
