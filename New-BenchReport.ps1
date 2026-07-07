[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-SuitePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
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

function Get-RelativeMarkdownPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'))
    $targetUri = [System.Uri]([System.IO.Path]::GetFullPath($TargetPath))
    return $baseUri.MakeRelativeUri($targetUri).ToString()
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

function Append-JsonObjectTable {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$JsonPath,
        [Parameter(Mandatory = $true)][string[]]$Fields
    )

    $obj = Read-JsonFileSafe -Path $JsonPath
    if (-not $obj) {
        return
    }

    [void]$Builder.AppendLine(("### {0}" -f $Title))
    [void]$Builder.AppendLine()
    [void]$Builder.AppendLine('| field | value |')
    [void]$Builder.AppendLine('|---|---|')
    foreach ($f in $Fields) {
        $v = Get-PropertyValue -Object $obj -Name $f
        if ($null -ne $v -and $v.ToString().Length -gt 0) {
            [void]$Builder.AppendLine(("| {0} | {1} |" -f $f, ($v.ToString() -replace '\|', '\|')))
        }
    }
    [void]$Builder.AppendLine()
}

function Get-CsvMetricStats {
    param([Parameter(Mandatory = $true)][string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        return @()
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ($rows.Count -eq 0) {
        return @()
    }

    $columns = @($rows[0].PSObject.Properties.Name)
    $stats = @()
    foreach ($column in $columns) {
        if ($column -eq 'timestamp') {
            continue
        }

        $values = New-Object System.Collections.Generic.List[double]
        foreach ($row in $rows) {
            $parsed = Try-ParseDouble -Value ([string]$row.$column)
            if ($null -ne $parsed) {
                [void]$values.Add($parsed)
            }
        }

        if ($values.Count -eq 0) {
            continue
        }

        $measure = $values | Measure-Object -Minimum -Maximum -Average
        $stats += [pscustomobject]@{
            Metric = $column
            Min    = [math]::Round([double]$measure.Minimum, 2)
            Max    = [math]::Round([double]$measure.Maximum, 2)
            Avg    = [math]::Round([double]$measure.Average, 2)
        }
    }

    return $stats
}

function Get-FramestatsSummary {
    param(
        [Parameter(Mandatory = $true)][string]$FramestatsPath,
        [int]$DurationSec
    )

    $summary = [ordered]@{
        Notes              = @()
        TotalFrames        = $null
        JankyFrames        = $null
        JankyPercent       = $null
        NaiveFpsEstimate   = $null
        SourceFormat       = $null
        ParsedFrameRows    = 0
    }

    if (-not (Test-Path -LiteralPath $FramestatsPath)) {
        $summary.Notes += 'framestats.txt not found.'
        return [pscustomobject]$summary
    }

    $content = Get-Content -LiteralPath $FramestatsPath -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        $summary.Notes += 'framestats.txt was empty.'
        return [pscustomobject]$summary
    }

    # Reference RPC6 / Android 14 output observed during development exposed
    # summary lines such as:
    #   Total frames rendered: 1234
    #   Janky frames: 56 (4.54%)
    # Some Android versions additionally include ---PROFILEDATA--- CSV rows with
    # nanosecond timestamps (IntendedVsync/Vsync/.../FrameCompleted). This parser
    # handles both formats and treats raw PROFILEDATA parsing as best-effort only.
    if ($content -match 'Total frames rendered:\s*(\d+)') {
        $summary.TotalFrames = [int]$Matches[1]
        $summary.SourceFormat = 'summary'
    }
    if ($content -match 'Janky frames:\s*(\d+)\s*\(([\d.]+)%\)') {
        $summary.JankyFrames = [int]$Matches[1]
        $summary.JankyPercent = [double]$Matches[2]
        if (-not $summary.SourceFormat) {
            $summary.SourceFormat = 'summary'
        }
    }

    $lines = $content -split "`r?`n"
    $profileHeader = $null
    $frameDurationsMs = New-Object System.Collections.Generic.List[double]
    foreach ($line in $lines) {
        if ($line -match '^(Flags|FrameTimelineVsyncId|IntendedVsync),') {
            $profileHeader = $line.Split(',')
            continue
        }

        if (-not $profileHeader) {
            continue
        }

        if ($line -notmatch '^\d') {
            continue
        }

        $parts = $line.Split(',')
        if ($parts.Count -ne $profileHeader.Count) {
            continue
        }

        $row = @{}
        for ($i = 0; $i -lt $profileHeader.Count; $i++) {
            $row[$profileHeader[$i]] = $parts[$i]
        }

        $startNs = $null
        foreach ($candidate in @('IntendedVsync', 'Vsync')) {
            if ($row.ContainsKey($candidate)) {
                $startNs = Try-ParseDouble -Value $row[$candidate]
                if ($null -ne $startNs) {
                    break
                }
            }
        }

        $endNs = $null
        foreach ($candidate in @('FrameCompleted', 'GpuCompleted', 'QueueBufferDuration')) {
            if ($row.ContainsKey($candidate)) {
                $endNs = Try-ParseDouble -Value $row[$candidate]
                if ($candidate -eq 'QueueBufferDuration' -and $null -ne $endNs) {
                    if ($null -ne $startNs) {
                        $endNs = $startNs + $endNs
                    }
                }
                if ($null -ne $endNs) {
                    break
                }
            }
        }

        if (($null -ne $startNs) -and ($null -ne $endNs) -and ($endNs -gt $startNs)) {
            [void]$frameDurationsMs.Add(($endNs - $startNs) / 1000000.0)
        }
    }

    if ($frameDurationsMs.Count -gt 0) {
        $summary.ParsedFrameRows = $frameDurationsMs.Count
        $avgMs = ($frameDurationsMs | Measure-Object -Average).Average
        if ($avgMs -gt 0) {
            $summary.NaiveFpsEstimate = [math]::Round(1000.0 / $avgMs, 2)
        }
        $summary.SourceFormat = 'profiledata'
    }
    elseif (($null -ne $summary.TotalFrames) -and $DurationSec -gt 0) {
        $summary.NaiveFpsEstimate = [math]::Round(($summary.TotalFrames / [double]$DurationSec), 2)
        $summary.Notes += "Naive FPS estimate used Total frames rendered / configured duration ($DurationSec s) because raw PROFILEDATA rows were unavailable."
    }

    if (($null -eq $summary.TotalFrames) -and ($null -eq $summary.JankyFrames)) {
        $summary.Notes += 'No parseable frame summary was found; format may differ on this Android build.'
    }

    return [pscustomobject]$summary
}

function Convert-StatsTableToMarkdown {
    param([object[]]$Stats)

    if (-not $Stats -or $Stats.Count -eq 0) {
        return "_No numeric telemetry rows were available._`n"
    }

    $lines = @(
        '| metric | min | max | avg |',
        '|---|---:|---:|---:|'
    )

    foreach ($row in $Stats) {
        $lines += ('| {0} | {1} | {2} | {3} |' -f $row.Metric, $row.Min, $row.Max, $row.Avg)
    }

    return ($lines -join "`n") + "`n"
}

$resolvedOutDir = Resolve-SuitePath -Path $OutDir
if (-not (Test-Path -LiteralPath $resolvedOutDir)) {
    throw "OutDir not found: $resolvedOutDir"
}

$deviceInfoPath = Join-Path $resolvedOutDir 'device-info.json'
$appsMetadataPath = Join-Path $resolvedOutDir 'apps-used.json'
$deviceInfo = $null
$appsMetadata = @()
if (Test-Path -LiteralPath $deviceInfoPath) {
    $deviceInfo = Get-Content -LiteralPath $deviceInfoPath -Raw | ConvertFrom-Json
}
if (Test-Path -LiteralPath $appsMetadataPath) {
    $loadedAppsMetadata = Get-Content -LiteralPath $appsMetadataPath -Raw | ConvertFrom-Json
    $appsMetadata = @($loadedAppsMetadata | ForEach-Object { $_ })
}

$normalizedAppsMetadata = @()
foreach ($item in $appsMetadata) {
    if ($item.PSObject.Properties['name']) {
        $normalizedAppsMetadata += $item
    }
    elseif ($item.PSObject.Properties['value']) {
        $normalizedAppsMetadata += @($item.value | ForEach-Object { $_ })
    }
}
if ($normalizedAppsMetadata.Count -gt 0) {
    $appsMetadata = $normalizedAppsMetadata
}

$appsByFolder = @{}
foreach ($app in $appsMetadata) {
    $folderKey = ($app.name -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($folderKey)) {
        $folderKey = 'item'
    }
    $appsByFolder[$folderKey] = $app
}

$appDirs = Get-ChildItem -LiteralPath $resolvedOutDir -Directory | Sort-Object Name
$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine('# Android Device Bench Report')
[void]$report.AppendLine()
[void]$report.AppendLine(("Generated: {0}" -f (Get-Date).ToString('o')))
[void]$report.AppendLine()

if ($deviceInfo) {
    [void]$report.AppendLine('## Device info')
    [void]$report.AppendLine()
    [void]$report.AppendLine('| field | value |')
    [void]$report.AppendLine('|---|---|')
    foreach ($field in @('configuredName', 'adbSerial', 'notes', 'productModel', 'androidRelease', 'buildFingerprint', 'wmSize', 'baselineBatteryLevel', 'suiteStartedAt')) {
        $value = Get-PropertyValue -Object $deviceInfo -Name $field
        if ($null -ne $value -and $value.ToString().Length -gt 0) {
            [void]$report.AppendLine(("| {0} | {1} |" -f $field, ($value.ToString() -replace '\|', '\|')))
        }
    }
    [void]$report.AppendLine()
}
else {
    [void]$report.AppendLine('## Device info')
    [void]$report.AppendLine()
    [void]$report.AppendLine('_device-info.json was not present, so baseline device details could not be included._')
    [void]$report.AppendLine()
}

$suiteStickPath = Join-Path $resolvedOutDir 'stick-drift.json'
$suiteHapticsPath = Join-Path $resolvedOutDir 'haptic-intensity.json'
if ((Test-Path -LiteralPath $suiteStickPath) -or (Test-Path -LiteralPath $suiteHapticsPath)) {
    [void]$report.AppendLine('## Suite-level manual checks')
    [void]$report.AppendLine()
    Append-JsonObjectTable -Builder $report -Title 'Stick drift check' -JsonPath $suiteStickPath -Fields @('status', 'node', 'durationSec', 'thresholdRule', 'pass')
    Append-JsonObjectTable -Builder $report -Title 'Haptic intensity check' -JsonPath $suiteHapticsPath -Fields @('status', 'accelerometerListed', 'vibratorService', 'reason', 'note')
}

foreach ($dir in $appDirs) {
    $telemetryPath = Join-Path $dir.FullName 'telemetry.csv'
    $cooldownPath = Join-Path $dir.FullName 'cooldown.csv'
    if ((-not (Test-Path -LiteralPath $telemetryPath)) -and (-not (Test-Path -LiteralPath $cooldownPath))) {
        continue
    }

    $appMetaPath = Join-Path $dir.FullName 'app-metadata.json'
    $appMeta = $null
    if (Test-Path -LiteralPath $appMetaPath) {
        $appMeta = Get-Content -LiteralPath $appMetaPath -Raw | ConvertFrom-Json
    }
    elseif ($appsByFolder.ContainsKey($dir.Name)) {
        $appMeta = $appsByFolder[$dir.Name]
    }

    $displayName = if ($appMeta) { [string](Get-PropertyValue -Object $appMeta -Name 'name') } else { $dir.Name }
    [void]$report.AppendLine(("## {0}" -f $displayName))
    [void]$report.AppendLine()

    if ($appMeta) {
        [void]$report.AppendLine('| field | value |')
        [void]$report.AppendLine('|---|---|')
        foreach ($field in @('package', 'type', 'durationSec', 'monkeyEnabled', 'monkeyPctTouch', 'monkeyPctMotion', 'skipMonkey', 'notes')) {
            $value = Get-PropertyValue -Object $appMeta -Name $field
            if ($null -ne $value -and $value.ToString().Length -gt 0) {
                [void]$report.AppendLine(("| {0} | {1} |" -f $field, ($value.ToString() -replace '\|', '\|')))
            }
        }
        [void]$report.AppendLine()
    }

    $launchShot = Join-Path $dir.FullName '00-launch.png'
    $endShot = Join-Path $dir.FullName '99-end.png'
    $links = @()
    if (Test-Path -LiteralPath $launchShot) {
        $links += "[Launch screenshot]($(Get-RelativeMarkdownPath -BasePath $resolvedOutDir -TargetPath $launchShot))"
    }
    if (Test-Path -LiteralPath $endShot) {
        $links += "[End screenshot]($(Get-RelativeMarkdownPath -BasePath $resolvedOutDir -TargetPath $endShot))"
    }
    if ($links.Count -gt 0) {
        [void]$report.AppendLine(($links -join ' | '))
        [void]$report.AppendLine()
    }

    [void]$report.AppendLine('### Active telemetry')
    [void]$report.AppendLine()
    [void]$report.Append((Convert-StatsTableToMarkdown -Stats (Get-CsvMetricStats -CsvPath $telemetryPath)))
    [void]$report.AppendLine()

    [void]$report.AppendLine('### Cooldown telemetry')
    [void]$report.AppendLine()
    [void]$report.Append((Convert-StatsTableToMarkdown -Stats (Get-CsvMetricStats -CsvPath $cooldownPath)))
    [void]$report.AppendLine()

    $framestatsDuration = 0
    if ($appMeta) {
        $durationValue = Get-PropertyValue -Object $appMeta -Name 'durationSec'
        if ($null -ne $durationValue) {
            $framestatsDuration = [int]$durationValue
        }
    }
    $framestats = Get-FramestatsSummary -FramestatsPath (Join-Path $dir.FullName 'framestats.txt') -DurationSec $framestatsDuration
    [void]$report.AppendLine('### Frame timing summary')
    [void]$report.AppendLine()
    [void]$report.AppendLine('| field | value |')
    [void]$report.AppendLine('|---|---|')
    foreach ($field in @('SourceFormat', 'TotalFrames', 'JankyFrames', 'JankyPercent', 'NaiveFpsEstimate', 'ParsedFrameRows')) {
        $value = $framestats.$field
        if ($null -ne $value -and $value.ToString().Length -gt 0) {
            [void]$report.AppendLine(("| {0} | {1} |" -f $field, $value))
        }
    }
    [void]$report.AppendLine()
    if ($framestats.Notes.Count -gt 0) {
        foreach ($note in $framestats.Notes) {
            [void]$report.AppendLine(("* {0}" -f $note))
        }
        [void]$report.AppendLine()
    }

    Append-JsonObjectTable -Builder $report -Title 'Storage speed test' -JsonPath (Join-Path $dir.FullName 'storage-speed.json') -Fields @('status', 'fileMB', 'writeMBps', 'readMBps', 'note')
    Append-JsonObjectTable -Builder $report -Title 'WiFi throughput test' -JsonPath (Join-Path $dir.FullName 'wifi-throughput.json') -Fields @('status', 'method', 'speedBytesPerSec', 'speedMbps', 'bytesRequested', 'url', 'note')
    Append-JsonObjectTable -Builder $report -Title 'Perfetto SurfaceView FPS prototype' -JsonPath (Join-Path $dir.FullName 'perfetto-fps.json') -Fields @('status', 'package', 'fpsEstimate', 'frameCount', 'sourceTable', 'note')

    foreach ($extraName in @('framestats.txt', 'batterystats.txt', 'battery-snapshot.txt', 'telemetry.csv', 'cooldown.csv', 'storage-speed.json', 'wifi-throughput.json', 'perfetto-fps.json', 'perfetto-capture.txt', 'perfetto-trace.perfetto-trace')) {
        $extraPath = Join-Path $dir.FullName $extraName
        if (Test-Path -LiteralPath $extraPath) {
            [void]$report.AppendLine(("* [{0}]({1})" -f $extraName, (Get-RelativeMarkdownPath -BasePath $resolvedOutDir -TargetPath $extraPath)))
        }
    }
    [void]$report.AppendLine()
}

$errorsLogPath = Join-Path $resolvedOutDir 'errors.log'
if (Test-Path -LiteralPath $errorsLogPath) {
    $errorsContent = Get-Content -LiteralPath $errorsLogPath -Raw
    [void]$report.AppendLine('## Errors / warnings')
    [void]$report.AppendLine()
    if ([string]::IsNullOrWhiteSpace($errorsContent)) {
        [void]$report.AppendLine('_No logged errors._')
    }
    else {
        [void]$report.AppendLine('```text')
        [void]$report.AppendLine($errorsContent.TrimEnd())
        [void]$report.AppendLine('```')
    }
    [void]$report.AppendLine()
}

$reportPath = Join-Path $resolvedOutDir 'report.md'
Write-Utf8NoBomFile -Path $reportPath -Content $report.ToString()
Write-Host ("Report written to {0}" -f $reportPath)
