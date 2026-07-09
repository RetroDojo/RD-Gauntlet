# Device Bench Dashboard (Flask + SQLite)

Local web dashboard for RD Gauntlet that launches benchmark jobs, tracks status, and browses reports/logs/results.

## Quick start

From `dashboard/`:

```powershell
pip install flask
python app.py
```

Then open: `http://127.0.0.1:8787`

Default bind is local-only (`127.0.0.1`) for safety.

## Optional host/port overrides

```powershell
python app.py --host 127.0.0.1 --port 8787
python app.py --host 0.0.0.0 --port 8787   # LAN sharing if desired
```

## What it does

- **Run** benchmark jobs via `Invoke-BenchmarkSuite.ps1`
- **Jobs** list with live status, cancel, log tail, report and results browsing
- **Compare** pipeline trigger (`New-ComparisonDataset.ps1` -> `New-ComparisonCharts.ps1`)
- **Tools**:
  - Open `pixelfit/console-to-screen-calculator.html` (RD PixelFit)
  - Run `Compare-Screenshots.py` between two existing screenshots

Runtime state:

- SQLite DB: `dashboard/jobs.db`
- Logs: `dashboard/logs/`
- Generated per-job runtime files: `dashboard/runtime/`

## Sharing with another power user

This dashboard depends on the existing bench-suite scripts/configs. Share:

1. Entire repo root (including the `dashboard/` folder)
2. Existing environment prerequisites already expected by this repo (`adb`, PowerShell, Python)
3. On their machine:
   - `pip install flask`
   - `python app.py` from `dashboard/`

No Node/npm/build tooling required.
