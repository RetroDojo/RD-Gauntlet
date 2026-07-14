[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CaptureIndexPath,
    [string]$OutputPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Broll.Common.psm1') -Force

function Escape-DrawtextText {
    param([Parameter(Mandatory = $true)][string]$Text)
    $value = $Text -replace '\\', '\\\\'
    $value = $value -replace ':', '\:'
    $value = $value -replace "'", "\\'"
    $value = $value -replace ',', '\,'
    return $value
}

Ensure-BrollCommand -Name 'ffmpeg'

$indexFullPath = Resolve-BrollPath -BasePath $PSScriptRoot -Path $CaptureIndexPath
if (-not (Test-Path -LiteralPath $indexFullPath)) {
    throw "Capture index not found: $indexFullPath"
}

$index = Get-Content -LiteralPath $indexFullPath -Raw | ConvertFrom-Json
$captures = @($index.captures | Select-Object -First 4)
if ($captures.Count -lt 2) {
    throw 'At least 2 captures are required to build a comparison grid.'
}

$resolvedOutput = if ($OutputPath) {
    Resolve-BrollPath -BasePath $PSScriptRoot -Path $OutputPath
}
else {
    $safeJob = ConvertTo-BrollSafeName -Value ([string]$index.jobName)
    Join-Path ([string]$index.outputRoot) ("{0}_comparison.mp4" -f $safeJob)
}
Ensure-BrollDirectory -Path (Split-Path -Parent $resolvedOutput)

$ffmpegArgs = @('-y')
$filterParts = @()
$mapParts = @()
$fontPath = 'C\:/Windows/Fonts/arial.ttf'

for ($i = 0; $i -lt $captures.Count; $i++) {
    $capture = $captures[$i]
    $clipPath = [string]$capture.clipPath
    $manifestPath = [string]$capture.manifestPath
    if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $clipPath))) {
        throw "Missing clip file: $clipPath"
    }
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Missing manifest file: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $label = if ($manifest.settingsSummary) { [string]$manifest.settingsSummary } else { [string]$capture.permutationId }
    $escapedLabel = Escape-DrawtextText -Text $label

    $ffmpegArgs += @('-i', $clipPath)
    $filterParts += ("[{0}:v]drawtext=fontfile='{1}':text='{2}':x=20:y=h-th-20:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.60:boxborderw=8[v{0}]" -f $i, $fontPath, $escapedLabel)
    $mapParts += "[v$i]"
}

$layoutFilter = switch ($captures.Count) {
    2 { "$($mapParts[0])$($mapParts[1])hstack=inputs=2[outv]" }
    3 { "$($mapParts[0])$($mapParts[1])$($mapParts[2])xstack=inputs=3:layout=0_0|w0_0|0_h0[outv]" }
    4 { "$($mapParts[0])$($mapParts[1])$($mapParts[2])$($mapParts[3])xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[outv]" }
    default { throw "Unsupported clip count: $($captures.Count). Use 2-4 clips." }
}
$filterParts += $layoutFilter
$filterComplex = $filterParts -join ';'

$ffmpegArgs += @(
    '-filter_complex', $filterComplex,
    '-map', '[outv]',
    '-map', '0:a?',
    '-c:v', 'libx264',
    '-crf', '18',
    '-preset', 'medium',
    '-pix_fmt', 'yuv420p',
    '-c:a', 'aac',
    '-shortest',
    $resolvedOutput
)

Invoke-BrollExternal -FilePath 'ffmpeg' -Arguments $ffmpegArgs -StepDescription 'Building comparison grid video' -DryRun:$DryRun | Out-Null
Write-BrollStatus -Message "Comparison video ready: $resolvedOutput"

return [pscustomobject]@{
    OutputPath        = $resolvedOutput
    CaptureIndexPath  = $indexFullPath
    IncludedClipCount = $captures.Count
    DryRun            = [bool]$DryRun
}
