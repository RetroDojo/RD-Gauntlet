# Comparison Dataset + First-Pass Charts (Phase 1)

This phase adds a shared, cross-run/cross-device comparison layer on top of existing run folders.

## Why long-format (tidy/tall) schema

`comparison-dataset.csv` / `.json` use one row per:

`(run, app, phase, metric)`

instead of one wide row with a fixed column per metric.

This is intentional because telemetry schemas differ by device (for example: one device may expose `gpu_busy_pct`, another may not; fan and thermal column names can differ completely). Long format avoids schema churn and makes filtering/querying simple (`metric_name == gpu_freq_hz` across every device that has it).

## Dataset schema

Columns:

- `run_id`
- `run_timestamp`
- `device_name`
- `adb_serial`
- `product_model`
- `android_release`
- `build_fingerprint`
- `app_name`
- `app_package`
- `app_type`
- `duration_sec`
- `phase` (`active` or `cooldown`)
- `metric_name`
- `min`
- `max`
- `avg`
- `sample_count`

Parsing semantics match `New-BenchReport.ps1`:

- skip `timestamp` column
- parse numeric values with invariant culture
- treat `NA` (and blank) as missing
- compute min/max/avg from available numeric samples only

## Run dataset build

From `tooling/device-bench-suite/`:

```powershell
.\New-ComparisonDataset.ps1 -ResultsRoot .\results
```

Outputs are rebuilt fresh each run by rescanning run folders with `device-info.json`:

- `.\results\comparison-dataset.csv`
- `.\results\comparison-dataset.json`

Design note: these files are **derived/regenerable views**; run folders are the source of truth.

## Run chart generation

```powershell
.\New-ComparisonCharts.ps1 -ResultsRoot .\results
```

Outputs:

- `.\results\comparison-charts\comparison-charts.html`
- `.\results\comparison-charts\comparison-charts-data.json`

### Charting implementation choice

This implementation uses a self-contained HTML file with Chart.js from CDN (no Python/matplotlib dependency required). In this environment, Python existed but `matplotlib` was not installed, so HTML/Chart.js was chosen for reliability and zero-install usage.

## What the charts show

1. **Cross-device bar chart**
   - Auto-detects a common metric present for the same app across all devices.
   - Preference order: `cpu_total_util_pct`, then `gpu_freq_hz`, then first available common metric.

2. **Per-device thermal timeline (active phase)**
   - Uses raw per-sample `telemetry.csv`.
   - Auto-selects one representative thermal zone per device with this heuristic:
     - pick highest-average zone among CPU-adjacent names (`cpu`, `big`, `lit`, `mid`, `apcpu`, `cpuss`)
     - if none match, fall back to hottest `tz_*` zone overall
   - Values over 1000 are interpreted as millidegree C and converted to C.

## Heuristic limitations

- Thermal zone auto-selection is heuristic and may not always pick the most editorially meaningful sensor for review/video storytelling.
- CDN-backed Chart.js requires internet access when opening the HTML file.
- Cross-device bar chart only compares metrics that truly exist on all compared devices for that app.

Human review of chart choices is still recommended before publishing website/video content.

## Publishing a static, shareable copy

```powershell
.\Export-StaticResults.ps1 -ResultsRoot .\results -PublishRoot .\results\publish
```

Outputs a self-contained folder (`.\results\publish\` by default):

- `index.html` -- simple branded landing page linking to the charts
- `comparison-charts.html` -- copy of the generated charts (works standalone, no dependency on `results/`)
- `comparison-charts-data.json` -- copy of the underlying chart data

This is intentionally the single choke point for anything shared externally. The chart-data schema
(`bar_data`: device/value/rows, `thermal_series`: device/run_id/app/thermal_zone/thermal_zone_avg_c/points)
is already public-safe -- no `adb_serial`, `build_fingerprint`, or `product_model` fields are present, only
friendly device labels (e.g. `RPC6`, `RG476H`). If the chart-data schema ever grows to include raw run
metadata, add redaction inside `Export-StaticResults.ps1` before copying.

The `results\publish\` folder can be zipped/uploaded anywhere (a personal site, GitHub Pages, etc.) as-is.
Building an actual hosted public-facing page (vs. a folder you upload yourself) is an explicitly deferred
follow-on feature -- see "Out of scope" below.

## Scope boundary

This is **Phase 1 only**: shared comparison dataset + first-pass charts.

Out of scope here:

- polished video-ready motion graphics
- embeddable production website widgets
- richer interaction/filters/themes
- hosted public-facing web page (a self-service static-file export is available now via
  `Export-StaticResults.ps1`; actual hosting/deployment is a deferred follow-on feature)

Those are follow-on Phase 2 tasks built on this dataset layer.
