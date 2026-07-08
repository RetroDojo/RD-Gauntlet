# Real-Capture Visual Grid

Ground-truth screenshot gallery builder for cross-device visual comparisons.

- Script: `Build-VisualGrid.py`
- Wrapper: `Invoke-VisualGrid.ps1`

## What it is (and what it is not)

This tool builds a static HTML grid from **real captured screenshots** in `results/<run-name>/<AppName>/*.png`.

Use it to compare what viewers actually care about on real hardware:

- scaling behavior
- letterboxing/pillarboxing
- aspect handling
- edge quality/sharpness differences
- color/contrast differences

Unlike `console-to-screen-calculator.html`, this is **not** math-only geometry simulation.  
The calculator predicts fit/scaling from panel and console specs; the visual grid shows real captures.

## Usage

### Python direct

```powershell
python .\Build-VisualGrid.py .\results\full-validation-retroarch .\results\full-validation-rg476h --out-html .\results\visual-grid\retroarch-cross-device.html
```

Filter by app/emulator name:

```powershell
python .\Build-VisualGrid.py .\results --out-html .\results\visual-grid\filtered.html --app-filter RetroArch --app-filter DraStic
```

### PowerShell wrapper

```powershell
.\Invoke-VisualGrid.ps1 -RunDir .\results\full-validation-retroarch,.\results\full-validation-rg476h -OutHtml .\results\visual-grid\retroarch-cross-device.html
```

With app filter:

```powershell
.\Invoke-VisualGrid.ps1 -RunDir .\results -OutHtml .\results\visual-grid\filtered.html -AppName RetroArch
```

## Output behavior

- Generates one standalone HTML file with inline CSS/JS.
- Image sources are written as paths relative to the output HTML location when possible.
- If an image is on a different drive/path where a relative path is not possible, file URI fallback is used.

## Current limitations

- The gallery quality is only as good as the screenshots you feed it.
- It does **not** automatically detect the emulator's internal render resolution or true content viewport.
- Device panel labels/diagonal/PPI depend on matching `device-info.json` + `device-specs.json`; unmatched runs still render but may show limited panel metadata.
