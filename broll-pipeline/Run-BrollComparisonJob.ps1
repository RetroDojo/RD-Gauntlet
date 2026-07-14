[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MatrixPath,
    [string]$OutputRoot,
    [string]$DeviceSerial,
    [switch]$DryRun,
    [switch]$SkipPostProcess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Broll.Common.psm1') -Force

Ensure-BrollCommand -Name 'adb'
Ensure-BrollCommand -Name 'scrcpy'
Ensure-BrollCommand -Name 'ffmpeg'

Write-BrollStatus -Message 'Starting RD-Gauntlet review B-roll comparison job.'

$captureScript = Join-Path $PSScriptRoot 'Invoke-BrollCapture.ps1'
$captureArgs = @{
    MatrixPath = $MatrixPath
    DryRun     = $DryRun
}
if ($OutputRoot) { $captureArgs.OutputRoot = $OutputRoot }
if ($DeviceSerial) { $captureArgs.DeviceSerial = $DeviceSerial }

$captureResult = & $captureScript @captureArgs
if (-not $captureResult) {
    throw 'Capture step did not return a capture index.'
}

if ($SkipPostProcess) {
    Write-BrollStatus -Message 'Skipping post-processing by request.'
    return [pscustomobject]@{
        CaptureIndexPath = [string](Join-Path ([string]$captureResult.outputRoot) 'captures-index.json')
        ComparisonPath   = $null
        DryRun           = [bool]$DryRun
        SkipPostProcess  = $true
    }
}

$postScript = Join-Path $PSScriptRoot 'New-BrollComparisonGrid.ps1'
$indexPath = Join-Path ([string]$captureResult.outputRoot) 'captures-index.json'
$postResult = & $postScript -CaptureIndexPath $indexPath -DryRun:$DryRun

return [pscustomobject]@{
    CaptureIndexPath = $indexPath
    ComparisonPath   = [string]$postResult.OutputPath
    DryRun           = [bool]$DryRun
    SkipPostProcess  = $false
}
