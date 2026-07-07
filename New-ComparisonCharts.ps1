[CmdletBinding()]
param(
    [string]$ResultsRoot = '.\results',
    [string]$DatasetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SuitePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Try-ParseDouble {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq 'NA') {
        return $null
    }

    $parsed = 0.0
    if ([double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $false)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Read-JsonFileSafe {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Normalize-AppsMetadata {
    param([Parameter(Mandatory = $false)]$AppsMetadata)

    $inputApps = @($AppsMetadata | ForEach-Object { $_ })
    $normalized = @()

    foreach ($item in $inputApps) {
        if ($item.PSObject.Properties['name']) {
            $normalized += $item
        }
        elseif ($item.PSObject.Properties['value']) {
            $normalized += @($item.value | ForEach-Object { $_ })
        }
    }

    return $normalized
}

function Find-RunDirectories {
    param([Parameter(Mandatory = $true)][string]$Root)
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'device-info.json' |
            ForEach-Object { $_.Directory.FullName } |
            Sort-Object -Unique
    )
}

function Find-AppTelemetryPath {
    param(
        [Parameter(Mandatory = $true)][string]$RunDir,
        [Parameter(Mandatory = $true)][string]$AppName,
        [Parameter(Mandatory = $false)][string]$AppPackage
    )

    $appDirs = Get-ChildItem -LiteralPath $RunDir -Directory | Sort-Object Name
    foreach ($appDir in $appDirs) {
        $telemetryPath = Join-Path $appDir.FullName 'telemetry.csv'
        if (-not (Test-Path -LiteralPath $telemetryPath)) {
            continue
        }

        $metaPath = Join-Path $appDir.FullName 'app-metadata.json'
        $meta = Read-JsonFileSafe -Path $metaPath
        if ($meta) {
            $metaName = [string](Get-PropertyValue -Object $meta -Name 'name')
            $metaPackage = [string](Get-PropertyValue -Object $meta -Name 'package')
            if (($metaName -eq $AppName) -or ((-not [string]::IsNullOrWhiteSpace($AppPackage)) -and ($metaPackage -eq $AppPackage))) {
                return $telemetryPath
            }
        }
    }

    $fallbackPath = Join-Path (Join-Path $RunDir $AppName) 'telemetry.csv'
    if (Test-Path -LiteralPath $fallbackPath) {
        return $fallbackPath
    }

    $normalized = ($AppName -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $normalizedPath = Join-Path (Join-Path $RunDir $normalized) 'telemetry.csv'
        if (Test-Path -LiteralPath $normalizedPath) {
            return $normalizedPath
        }
    }

    return $null
}

function Get-ThermalTimelineSelection {
    param([Parameter(Mandatory = $true)][string]$TelemetryPath)

    try {
        if (-not (Test-Path -LiteralPath $TelemetryPath)) {
            return $null
        }

        $rows = @(Import-Csv -LiteralPath $TelemetryPath)
        if ($rows.Count -eq 0) {
            return $null
        }

        $columns = @($rows[0].PSObject.Properties.Name)
        $thermalColumns = @($columns | Where-Object { $_ -match '^tz_.*(?:__c|_c)$' })
        if ($thermalColumns.Count -eq 0) {
            return $null
        }

        $stats = @()
        foreach ($col in $thermalColumns) {
            $values = New-Object System.Collections.Generic.List[double]
            foreach ($row in $rows) {
                $parsed = Try-ParseDouble -Value ([string]$row.$col)
                if ($null -ne $parsed) {
                    if ([math]::Abs([double]$parsed) -gt 1000) {
                        $parsed = [double]$parsed / 1000.0
                    }
                    [void]$values.Add([double]$parsed)
                }
            }

            if ($values.Count -eq 0) {
                continue
            }

            $avg = ($values | Measure-Object -Average).Average
            $isCpuLike = ($col -match '(cpu|big|little|lit|mid|apcpu|cpuss)')
            $stats += [pscustomobject]@{
                name      = $col
                avg       = [double]$avg
                isCpuLike = $isCpuLike
            }
        }

        if ($stats.Count -eq 0) {
            return $null
        }

        $candidates = @($stats | Where-Object { $_.isCpuLike })
        if ($candidates.Count -eq 0) {
            $candidates = $stats
        }

        $chosen = $candidates | Sort-Object avg -Descending | Select-Object -First 1
        if (-not $chosen) {
            return $null
        }

        $points = @()
        $startTime = $null
        foreach ($row in $rows) {
            $value = Try-ParseDouble -Value ([string]$row.($chosen.name))
            if ($null -eq $value) {
                continue
            }

            $value = [double]$value
            if ([math]::Abs($value) -gt 1000) {
                $value = $value / 1000.0
            }

            $timestamp = [string]$row.timestamp
            $seconds = $null
            if (-not [string]::IsNullOrWhiteSpace($timestamp)) {
                try {
                    $parsedTs = [datetime]$timestamp
                    if ($null -eq $startTime) {
                        $startTime = $parsedTs
                    }
                    $seconds = [math]::Round(($parsedTs - $startTime).TotalSeconds, 1)
                }
                catch {
                    $seconds = $null
                }
            }

            if ($null -eq $seconds) {
                $seconds = $points.Count
            }

            $points += [pscustomobject]@{
                x = $seconds
                y = [math]::Round($value, 2)
            }
        }

        return [pscustomobject]@{
            column = $chosen.name
            avg_c  = [math]::Round([double]$chosen.avg, 2)
            points = @($points)
        }
    }
    catch {
        throw "Thermal timeline parse failed for '$TelemetryPath': $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    }
}

$resolvedResultsRoot = Resolve-SuitePath -Path $ResultsRoot
if (-not (Test-Path -LiteralPath $resolvedResultsRoot)) {
    throw "Results root not found: $resolvedResultsRoot"
}

$resolvedDatasetPath = if ([string]::IsNullOrWhiteSpace($DatasetPath)) {
    Join-Path $resolvedResultsRoot 'comparison-dataset.json'
}
else {
    Resolve-SuitePath -Path $DatasetPath
}

if (-not (Test-Path -LiteralPath $resolvedDatasetPath)) {
    throw "Dataset file not found: $resolvedDatasetPath. Run New-ComparisonDataset.ps1 first."
}

$datasetRows = @(Get-Content -LiteralPath $resolvedDatasetPath -Raw | ConvertFrom-Json)
if ($datasetRows.Count -eq 0) {
    throw "Dataset was empty: $resolvedDatasetPath"
}

$activeRows = @($datasetRows | Where-Object { $_.phase -eq 'active' })
if ($activeRows.Count -eq 0) {
    throw "Dataset has no active-phase rows."
}

$deviceNames = @($activeRows | Select-Object -ExpandProperty device_name -Unique)
if ($deviceNames.Count -lt 2) {
    throw "Need at least two devices for cross-device comparison."
}

$appCandidates = @(
    $activeRows |
        Group-Object app_name |
        Where-Object { (@($_.Group | Select-Object -ExpandProperty device_name -Unique).Count -eq $deviceNames.Count) } |
        ForEach-Object { $_.Name } |
        Sort-Object
)
if ($appCandidates.Count -eq 0) {
    throw "No app appears across all devices in active-phase dataset."
}

$selectedApp = $appCandidates[0]
$appRows = @($activeRows | Where-Object { $_.app_name -eq $selectedApp })

$metricsPresentPerDevice = @{}
foreach ($d in $deviceNames) {
    $metricsPresentPerDevice[$d] = @($appRows | Where-Object { $_.device_name -eq $d } | Select-Object -ExpandProperty metric_name -Unique)
}

$commonMetrics = @($metricsPresentPerDevice[$deviceNames[0]])
foreach ($d in $deviceNames[1..($deviceNames.Count - 1)]) {
    $commonMetrics = @($commonMetrics | Where-Object { $metricsPresentPerDevice[$d] -contains $_ })
}

if ($commonMetrics.Count -eq 0) {
    throw "No common metrics found across devices for app '$selectedApp'."
}

$preferredMetrics = @('cpu_total_util_pct', 'gpu_freq_hz')
$selectedMetric = $null
foreach ($preferred in $preferredMetrics) {
    if ($commonMetrics -contains $preferred) {
        $selectedMetric = $preferred
        break
    }
}
if (-not $selectedMetric) {
    $selectedMetric = ($commonMetrics | Sort-Object)[0]
}

$barData = @()
foreach ($d in $deviceNames) {
    $rows = @($appRows | Where-Object { $_.device_name -eq $d -and $_.metric_name -eq $selectedMetric })
    if ($rows.Count -eq 0) {
        continue
    }
    $value = ($rows | Measure-Object -Property avg -Average).Average
    $barData += [pscustomobject]@{
        device = $d
        value = [math]::Round([double]$value, 2)
        rows = $rows.Count
    }
}

if ($barData.Count -lt 2) {
    throw "Insufficient data points for cross-device bar chart metric '$selectedMetric'."
}

$runLookup = @{}
foreach ($runDir in (Find-RunDirectories -Root $resolvedResultsRoot)) {
    $deviceInfo = Read-JsonFileSafe -Path (Join-Path $runDir 'device-info.json')
    if (-not $deviceInfo) {
        continue
    }
    $runId = Split-Path -Path $runDir -Leaf
    $runLookup[$runId] = [pscustomobject]@{
        run_dir = $runDir
        configuredName = [string](Get-PropertyValue -Object $deviceInfo -Name 'configuredName')
    }
}

$timelineSeries = @()
foreach ($device in $deviceNames) {
    $deviceRows = @(
        $appRows |
            Where-Object { $_.device_name -eq $device } |
            Sort-Object run_timestamp -Descending
    )
    if ($deviceRows.Count -eq 0) {
        continue
    }

    $reference = $deviceRows[0]
    $runInfo = $null
    if ($runLookup.ContainsKey($reference.run_id)) {
        $runInfo = $runLookup[$reference.run_id]
    }
    if (-not $runInfo) {
        continue
    }

    $telemetryPath = Find-AppTelemetryPath -RunDir $runInfo.run_dir -AppName ([string]$reference.app_name) -AppPackage ([string]$reference.app_package)
    if (-not $telemetryPath) {
        continue
    }

    $timeline = Get-ThermalTimelineSelection -TelemetryPath $telemetryPath
    if (-not $timeline -or $timeline.points.Count -eq 0) {
        continue
    }

    $timelineSeries += [pscustomobject]@{
        device = $device
        run_id = [string]$reference.run_id
        app = [string]$reference.app_name
        thermal_zone = $timeline.column
        thermal_zone_avg_c = $timeline.avg_c
        points = $timeline.points
    }
}

if ($timelineSeries.Count -eq 0) {
    throw "No thermal timeline series could be generated."
}

$chartsDir = Join-Path $resolvedResultsRoot 'comparison-charts'
if (-not (Test-Path -LiteralPath $chartsDir)) {
    New-Item -ItemType Directory -Path $chartsDir | Out-Null
}

$chartPayload = [pscustomobject]@{
    generated_at = (Get-Date).ToString('o')
    app_name = $selectedApp
    metric_name = $selectedMetric
    bar_data = @($barData)
    thermal_series = @($timelineSeries)
    heuristic_note = 'Thermal zone heuristic picks the highest-average CPU-adjacent tz_* column (cpu/big/lit/mid/apcpu/cpuss). If none exist, it falls back to the hottest tz_* column. Values above 1000 are treated as millidegree C and converted to C.'
}

$payloadJson = $chartPayload | ConvertTo-Json -Depth 10
$payloadJs = $payloadJson -replace '</', '<\/'

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Device Bench Comparison Charts</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1, h2 { margin-bottom: 8px; }
    p, li { line-height: 1.4; }
    .chart-wrap { margin: 20px 0 28px; border: 1px solid #ddd; padding: 12px; border-radius: 8px; }
    canvas { width: 100% !important; max-width: 1100px; height: 420px !important; }
    code { background: #f5f5f5; padding: 0 4px; }
  </style>
</head>
<body>
  <h1>Device Bench Comparison Charts</h1>
  <p>Generated at <code id="generatedAt"></code></p>
  <p id="metricSummary"></p>
  <div class="chart-wrap">
    <h2>Cross-device bar comparison</h2>
    <canvas id="crossDeviceBar"></canvas>
  </div>
  <div class="chart-wrap">
    <h2>Per-device thermal timeline (active phase)</h2>
    <canvas id="thermalTimeline"></canvas>
  </div>
  <h2>Thermal zone heuristic</h2>
  <p id="heuristic"></p>
  <ul id="thermalLegend"></ul>

  <script>
    const payload = $payloadJs;
    document.getElementById('generatedAt').textContent = payload.generated_at;
    document.getElementById('metricSummary').textContent =
      'App: ' + payload.app_name + ' | Metric: ' + payload.metric_name + ' (average from comparison dataset)';
    document.getElementById('heuristic').textContent = payload.heuristic_note;

    const barCtx = document.getElementById('crossDeviceBar').getContext('2d');
    new Chart(barCtx, {
      type: 'bar',
      data: {
        labels: payload.bar_data.map(x => x.device),
        datasets: [{
          label: 'Average ' + payload.metric_name,
          data: payload.bar_data.map(x => x.value),
          backgroundColor: ['#3b82f6', '#ef4444', '#10b981', '#a855f7', '#f59e0b']
        }]
      },
      options: {
        responsive: true,
        scales: {
          y: { beginAtZero: true, title: { display: true, text: payload.metric_name } }
        }
      }
    });

    const thermalLegend = document.getElementById('thermalLegend');
    payload.thermal_series.forEach(series => {
      const li = document.createElement('li');
      li.textContent = series.device + ': ' + series.thermal_zone + ' (avg ' + series.thermal_zone_avg_c + '°C)';
      thermalLegend.appendChild(li);
    });

    const thermalCtx = document.getElementById('thermalTimeline').getContext('2d');
    new Chart(thermalCtx, {
      type: 'line',
      data: {
        datasets: payload.thermal_series.map((series, idx) => ({
          label: series.device + ' - ' + series.thermal_zone,
          data: series.points.map(p => ({ x: p.x, y: p.y })),
          borderColor: ['#2563eb', '#dc2626', '#059669', '#7c3aed', '#d97706'][idx % 5],
          pointRadius: 0,
          borderWidth: 2,
          fill: false
        }))
      },
      options: {
        responsive: true,
        parsing: false,
        scales: {
          x: { type: 'linear', title: { display: true, text: 'Seconds from active-phase start' } },
          y: { title: { display: true, text: 'Temperature (°C)' } }
        }
      }
    });
  </script>
</body>
</html>
"@

$htmlPath = Join-Path $chartsDir 'comparison-charts.html'
$dataPath = Join-Path $chartsDir 'comparison-charts-data.json'
Write-Utf8NoBomFile -Path $htmlPath -Content $html
Write-Utf8NoBomFile -Path $dataPath -Content ($payloadJson + "`r`n")

Write-Host ("Charts HTML: {0}" -f $htmlPath)
Write-Host ("Charts data JSON: {0}" -f $dataPath)
Write-Host ("Bar metric: {0}" -f $selectedMetric)
Write-Host ("Thermal series count: {0}" -f $timelineSeries.Count)
