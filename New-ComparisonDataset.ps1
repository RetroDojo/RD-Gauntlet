[CmdletBinding()]
param(
    [string]$ResultsRoot = '.\results'
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

function Get-MetricDefinitions {
    # Loads the declarative metric-metadata file (proportion/scale/quantifier), modeled on the
    # Phoronix Test Suite test-profile schema's HIB/LIB/ABSTRACT vocabulary -- see
    # docs/result-schema-conventions.md. Returns an ordered list of {Pattern, Label, ResultScale,
    # Proportion, ResultQuantifier} so callers can pattern-match a metric_name against it.
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $raw = Read-JsonFileSafe -Path $Path
    if (-not $raw -or -not $raw.PSObject.Properties['definitions']) {
        return @()
    }

    return @($raw.definitions | ForEach-Object {
        [pscustomobject]@{
            Pattern          = [string]$_.pattern
            Label            = [string](Get-PropertyValue -Object $_ -Name 'label')
            ResultScale      = [string](Get-PropertyValue -Object $_ -Name 'resultScale')
            Proportion       = [string](Get-PropertyValue -Object $_ -Name 'proportion')
            ResultQuantifier = [string](Get-PropertyValue -Object $_ -Name 'resultQuantifier')
        }
    })
}

function Resolve-MetricMetadata {
    # First-match-wins regex lookup against metric_name. Unmatched metrics (e.g. a new sysfs
    # column not yet catalogued) fall back to ABSTRACT/unknown rather than erroring, so this
    # never blocks dataset generation -- it's an enrichment, not a validation gate.
    param(
        [Parameter(Mandatory = $true)][string]$MetricName,
        [Parameter(Mandatory = $true)][object[]]$Definitions
    )

    foreach ($def in $Definitions) {
        if ([string]::IsNullOrWhiteSpace($def.Pattern)) {
            continue
        }
        if ($MetricName -match $def.Pattern) {
            return $def
        }
    }

    return [pscustomobject]@{
        Pattern          = $null
        Label            = $MetricName
        ResultScale      = 'unknown'
        Proportion       = 'ABSTRACT'
        ResultQuantifier = 'AVG'
    }
}

function Get-CsvHeaderFromSiblingTelemetry {
    # cooldown.csv is written by the same telemetry-monitor.sh header logic as telemetry.csv
    # for a given app/device, so a sibling telemetry.csv in the same folder is a reliable
    # source of the real column names when cooldown.csv itself is missing its header row
    # (observed race: the remote monitor script's header write occasionally lost against a
    # stale/overlapping process, leaving the CSV starting directly with a data row).
    param([Parameter(Mandatory = $true)][string]$CsvPath)

    $siblingTelemetry = Join-Path (Split-Path -Parent $CsvPath) 'telemetry.csv'
    if ((Split-Path -Leaf $CsvPath) -ne 'telemetry.csv' -and (Test-Path -LiteralPath $siblingTelemetry)) {
        $firstLine = Get-Content -LiteralPath $siblingTelemetry -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -and ($firstLine -match '^[a-zA-Z_]')) {
            return @($firstLine -split ',' | ForEach-Object { $_.Trim('"') })
        }
    }
    return $null
}

function Get-CsvMetricStats {
    param([Parameter(Mandatory = $true)][string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        return @()
    }

    $rows = $null
    try {
        $rows = @(Import-Csv -LiteralPath $CsvPath)
    }
    catch {
        # Likely a headerless CSV (first line is a data row, not column names) -- this can
        # produce duplicate/invalid member names that Import-Csv rejects outright. Recover by
        # borrowing the header from a sibling telemetry.csv (same schema, same device/app),
        # falling back to generic positional names if no sibling header is available.
        $recoveredHeader = Get-CsvHeaderFromSiblingTelemetry -CsvPath $CsvPath
        if (-not $recoveredHeader) {
            $firstDataLine = Get-Content -LiteralPath $CsvPath -TotalCount 1 -ErrorAction SilentlyContinue
            $fieldCount = if ($firstDataLine) { @($firstDataLine -split ',').Count } else { 0 }
            $recoveredHeader = @(1..$fieldCount | ForEach-Object { "col_$_" })
        }
        Write-Warning ("Recovered headerless CSV using {0} columns: {1}" -f $recoveredHeader.Count, $CsvPath)
        $rows = @(Import-Csv -LiteralPath $CsvPath -Header $recoveredHeader)
    }

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
            metric_name  = $column
            min          = [math]::Round([double]$measure.Minimum, 2)
            max          = [math]::Round([double]$measure.Maximum, 2)
            avg          = [math]::Round([double]$measure.Average, 2)
            sample_count = $values.Count
        }
    }

    return $stats
}

$resolvedResultsRoot = Resolve-SuitePath -Path $ResultsRoot
if (-not (Test-Path -LiteralPath $resolvedResultsRoot)) {
    throw "Results root not found: $resolvedResultsRoot"
}

$metricDefinitionsPath = Resolve-SuitePath -Path '.\metric-definitions.json'
$metricDefinitions = Get-MetricDefinitions -Path $metricDefinitionsPath

$runDirs = @(
    Get-ChildItem -LiteralPath $resolvedResultsRoot -Recurse -File -Filter 'device-info.json' |
        ForEach-Object { $_.Directory.FullName } |
        Sort-Object -Unique
)

$datasetRows = New-Object System.Collections.Generic.List[object]

foreach ($runDir in $runDirs) {
    $deviceInfoPath = Join-Path $runDir 'device-info.json'
    $deviceInfo = Read-JsonFileSafe -Path $deviceInfoPath
    if (-not $deviceInfo) {
        continue
    }

    $appsMetadataPath = Join-Path $runDir 'apps-used.json'
    $appsMetadata = Normalize-AppsMetadata -AppsMetadata (Read-JsonFileSafe -Path $appsMetadataPath)
    $appsByFolder = @{}
    foreach ($app in $appsMetadata) {
        $folderKey = ($app.name -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
        if ([string]::IsNullOrWhiteSpace($folderKey)) {
            $folderKey = 'item'
        }
        $appsByFolder[$folderKey] = $app
    }

    $runId = Split-Path -Path $runDir -Leaf
    $runTimestamp = [string](Get-PropertyValue -Object $deviceInfo -Name 'suiteStartedAt')
    if ([string]::IsNullOrWhiteSpace($runTimestamp)) {
        $runTimestamp = (Get-Item -LiteralPath $runDir).LastWriteTime.ToString('o')
    }

    $appDirs = Get-ChildItem -LiteralPath $runDir -Directory | Sort-Object Name
    foreach ($appDir in $appDirs) {
        $telemetryPath = Join-Path $appDir.FullName 'telemetry.csv'
        $cooldownPath = Join-Path $appDir.FullName 'cooldown.csv'

        if ((-not (Test-Path -LiteralPath $telemetryPath)) -and (-not (Test-Path -LiteralPath $cooldownPath))) {
            continue
        }

        $appMetaPath = Join-Path $appDir.FullName 'app-metadata.json'
        $appMeta = Read-JsonFileSafe -Path $appMetaPath
        if ((-not $appMeta) -and $appsByFolder.ContainsKey($appDir.Name)) {
            $appMeta = $appsByFolder[$appDir.Name]
        }

        $durationSecValue = Get-PropertyValue -Object $appMeta -Name 'durationSec'
        $durationSecParsed = Try-ParseDouble -Value ([string]$durationSecValue)
        $durationSec = $null
        if ($null -ne $durationSecParsed) {
            $durationSec = [int][math]::Round($durationSecParsed, 0)
        }

        $commonFields = @{
            run_id           = $runId
            run_timestamp    = $runTimestamp
            device_name      = [string](Get-PropertyValue -Object $deviceInfo -Name 'configuredName')
            adb_serial       = [string](Get-PropertyValue -Object $deviceInfo -Name 'adbSerial')
            product_model    = [string](Get-PropertyValue -Object $deviceInfo -Name 'productModel')
            android_release  = [string](Get-PropertyValue -Object $deviceInfo -Name 'androidRelease')
            build_fingerprint = [string](Get-PropertyValue -Object $deviceInfo -Name 'buildFingerprint')
            app_name         = if ($appMeta) { [string](Get-PropertyValue -Object $appMeta -Name 'name') } else { $appDir.Name }
            app_package      = if ($appMeta) { [string](Get-PropertyValue -Object $appMeta -Name 'package') } else { '' }
            app_type         = if ($appMeta) { [string](Get-PropertyValue -Object $appMeta -Name 'type') } else { '' }
            duration_sec     = $durationSec
            # Semantic test-versioning convention borrowed from PTS (see
            # docs/result-schema-conventions.md): a changed test_version means results from
            # before/after should not be directly compared. Empty when apps.json predates this
            # field or app-metadata.json wasn't captured with it.
            test_version     = if ($appMeta) { [string](Get-PropertyValue -Object $appMeta -Name 'testVersion') } else { '' }
        }

        foreach ($phaseInfo in @(
            @{ phase = 'active'; path = $telemetryPath },
            @{ phase = 'cooldown'; path = $cooldownPath }
        )) {
            $stats = Get-CsvMetricStats -CsvPath $phaseInfo.path
            foreach ($metric in $stats) {
                $metricMeta = Resolve-MetricMetadata -MetricName $metric.metric_name -Definitions $metricDefinitions
                $datasetRows.Add([pscustomobject]@{
                    run_id            = $commonFields.run_id
                    run_timestamp     = $commonFields.run_timestamp
                    device_name       = $commonFields.device_name
                    adb_serial        = $commonFields.adb_serial
                    product_model     = $commonFields.product_model
                    android_release   = $commonFields.android_release
                    build_fingerprint = $commonFields.build_fingerprint
                    app_name          = $commonFields.app_name
                    app_package       = $commonFields.app_package
                    app_type          = $commonFields.app_type
                    duration_sec      = $commonFields.duration_sec
                    test_version      = $commonFields.test_version
                    phase             = $phaseInfo.phase
                    metric_name       = $metric.metric_name
                    min               = $metric.min
                    max               = $metric.max
                    avg               = $metric.avg
                    sample_count      = $metric.sample_count
                    # Enrichment columns from metric-definitions.json (PTS-style HIB/LIB/ABSTRACT
                    # vocabulary) -- unmatched metrics fall back to ABSTRACT/unknown rather than
                    # failing, so this never blocks dataset generation.
                    proportion        = $metricMeta.Proportion
                    result_scale      = $metricMeta.ResultScale
                    result_quantifier = $metricMeta.ResultQuantifier
                })
            }
        }
    }
}

$orderedRows = @(
    $datasetRows |
        Sort-Object run_timestamp, run_id, device_name, app_name, phase, metric_name
)

$csvPath = Join-Path $resolvedResultsRoot 'comparison-dataset.csv'
$jsonPath = Join-Path $resolvedResultsRoot 'comparison-dataset.json'

# The comparison dataset is a derived/regenerable view. Each run rebuilds both files from
# source-of-truth result folders instead of incrementally mutating prior dataset artifacts.
$header = 'run_id,run_timestamp,device_name,adb_serial,product_model,android_release,build_fingerprint,app_name,app_package,app_type,duration_sec,test_version,phase,metric_name,min,max,avg,sample_count,proportion,result_scale,result_quantifier'
if ($orderedRows.Count -eq 0) {
    Write-Utf8NoBomFile -Path $csvPath -Content ($header + "`r`n")
    Write-Utf8NoBomFile -Path $jsonPath -Content "[]`r`n"
}
else {
    $csvContent = ($orderedRows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    Write-Utf8NoBomFile -Path $csvPath -Content ($csvContent + "`r`n")
    $jsonContent = $orderedRows | ConvertTo-Json -Depth 6
    Write-Utf8NoBomFile -Path $jsonPath -Content ($jsonContent + "`r`n")
}

Write-Host ("Comparison CSV: {0}" -f $csvPath)
Write-Host ("Comparison JSON: {0}" -f $jsonPath)
Write-Host ("Rows: {0}" -f $orderedRows.Count)
