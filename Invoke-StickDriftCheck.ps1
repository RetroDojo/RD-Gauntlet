[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$OutPath = ".\stick-drift.json",
    [int]$DurationSec = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & adb @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $old
    }
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: adb $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    return (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
}

function Get-StickAxisRanges {
    param([string]$Text)
    $devices = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^add device \d+:\s+(?<node>/dev/input/event\d+)') {
            if ($current) { $devices.Add($current) }
            $current = [ordered]@{ Node = $Matches.node; Axes = @{} }
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^\s*ABS_(?<axis>X|Y|RX|RY)\s*:\s*value\s+\d+,\s*min\s+(?<min>-?\d+),\s*max\s+(?<max>-?\d+)') {
            $current.Axes["ABS_$($Matches.axis)"] = [ordered]@{ Min = [int]$Matches.min; Max = [int]$Matches.max }
        }
    }
    if ($current) { $devices.Add($current) }
    return $devices
}

Write-Host "DO NOT TOUCH THE CONTROLLER - sampling idle drift for $DurationSec seconds..."
for ($i = 3; $i -ge 1; $i--) {
    Write-Host ("Starting in {0}..." -f $i)
    Start-Sleep -Seconds 1
}

$info = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'getevent', '-pl')
$devices = Get-StickAxisRanges -Text $info
$target = $devices | Where-Object { $_.Axes.ContainsKey('ABS_X') -and $_.Axes.ContainsKey('ABS_Y') } | Select-Object -First 1
if (-not $target) {
    [System.IO.File]::WriteAllText($OutPath, '{"status":"unsupported","reason":"no_abs_stick_device_found"}', [System.Text.UTF8Encoding]::new($false))
    exit 0
}

$node = [string]$target.Node
$capture = Invoke-Adb -Arguments @('-s', $Serial, 'shell', "getevent -lt $node > /data/local/tmp/stick_drift_raw.txt 2>/dev/null & pid=`$!; sleep $DurationSec; kill -INT `$pid >/dev/null 2>&1; wait `$pid >/dev/null 2>&1; cat /data/local/tmp/stick_drift_raw.txt; rm -f /data/local/tmp/stick_drift_raw.txt")

$map = @{ '0000' = 'ABS_X'; '0001' = 'ABS_Y'; '0003' = 'ABS_RX'; '0004' = 'ABS_RY' }
$samples = @{
    ABS_X  = New-Object System.Collections.Generic.List[int]
    ABS_Y  = New-Object System.Collections.Generic.List[int]
    ABS_RX = New-Object System.Collections.Generic.List[int]
    ABS_RY = New-Object System.Collections.Generic.List[int]
}
foreach ($line in ($capture -split "`r?`n")) {
    if ($line -match ':\s+0003\s+(?<code>[0-9a-fA-F]{4})\s+(?<value>[0-9a-fA-F]{8})') {
        $code = $Matches.code.ToLowerInvariant()
        if ($map.ContainsKey($code)) {
            [void]$samples[$map[$code]].Add([Convert]::ToInt32($Matches.value, 16))
        }
    }
}

$axes = @()
foreach ($axis in @('ABS_X', 'ABS_Y', 'ABS_RX', 'ABS_RY')) {
    if (-not $target.Axes.ContainsKey($axis)) { continue }
    $r = $target.Axes[$axis]
    $center = [math]::Round(($r.Min + $r.Max) / 2.0, 0)
    $span = [math]::Max(1, $r.Max - $r.Min)
    $threshold = [math]::Max(4, [math]::Round($span * 0.03, 0))
    $vals = $samples[$axis]
    if ($vals.Count -eq 0) {
        $axes += [pscustomobject]@{ axis = $axis; sampleCount = 0; center = $center; maxDeviation = $null; threshold = $threshold; drift = $null }
        continue
    }
    $maxDev = 0
    foreach ($v in $vals) {
        $dev = [math]::Abs($v - $center)
        if ($dev -gt $maxDev) { $maxDev = $dev }
    }
    $axes += [pscustomobject]@{ axis = $axis; sampleCount = $vals.Count; center = [int]$center; maxDeviation = [int]$maxDev; threshold = [int]$threshold; drift = ($maxDev -gt $threshold) }
}

$hasDrift = $axes | Where-Object { $_.drift -eq $true } | Select-Object -First 1
$result = [ordered]@{
    status = 'ok'
    node = $node
    durationSec = $DurationSec
    thresholdRule = 'max(4, 3% of axis span)'
    pass = (-not $hasDrift)
    axes = $axes
}
$resolvedOut = if ([System.IO.Path]::IsPathRooted($OutPath)) { $OutPath } else { Join-Path (Get-Location) $OutPath }
[System.IO.File]::WriteAllText($resolvedOut, (ConvertTo-Json -InputObject $result -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0}" -f $OutPath)
