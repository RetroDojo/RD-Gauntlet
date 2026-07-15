[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MatrixPath,
    [string]$OutputRoot,
    [string]$DeviceSerial,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Broll.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConfigPatcher.psm1') -Force

function Get-GpuMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [switch]$DryRun
    )

    if ($DryRun) {
        return [pscustomobject]@{
            mode                   = 'dry-run'
            roBoardPlatform        = '<unknown>'
            roHardwareEgl          = '<unknown>'
            roHardwareVulkan       = '<unknown>'
            roGfxDriver0           = '<unknown>'
            surfaceFlingerRenderer = '<unknown>'
        }
    }

    $platform = (Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'getprop', 'ro.board.platform') -StepDescription 'Reading ro.board.platform').Output.Trim()
    $egl = (Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'getprop', 'ro.hardware.egl') -StepDescription 'Reading ro.hardware.egl' -AllowFailure).Output.Trim()
    $vulkan = (Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'getprop', 'ro.hardware.vulkan') -StepDescription 'Reading ro.hardware.vulkan' -AllowFailure).Output.Trim()
    $driver0 = (Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'getprop', 'ro.gfx.driver.0') -StepDescription 'Reading ro.gfx.driver.0' -AllowFailure).Output.Trim()
    $sf = (Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'dumpsys', 'SurfaceFlinger') -StepDescription 'Reading SurfaceFlinger renderer' -AllowFailure).Output
    $sfLine = (($sf -split "`r?`n") | Where-Object { $_ -match '(?i)(gles|vulkan|renderengine)' } | Select-Object -First 1)

    return [pscustomobject]@{
        mode                   = 'live'
        roBoardPlatform        = $platform
        roHardwareEgl          = $egl
        roHardwareVulkan       = $vulkan
        roGfxDriver0           = $driver0
        surfaceFlingerRenderer = $sfLine
    }
}

function Invoke-LaunchEmulator {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [switch]$DryRun
    )

    if (-not $Target.ContainsKey('package')) {
        throw 'target.package is required.'
    }

    $package = [string]$Target.package
    Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'am', 'force-stop', $package) -StepDescription "Force-stopping $package" -DryRun:$DryRun | Out-Null

    if ($Target.ContainsKey('launch') -and $Target.launch) {
        $launch = ConvertTo-BrollHashtable -InputObject $Target.launch
        if ($launch.ContainsKey('intent') -and $launch.intent) {
            $intent = ConvertTo-BrollHashtable -InputObject $launch.intent
            $args = @('shell', 'am', 'start')
            if ($intent.ContainsKey('action') -and $intent.action) {
                $args += @('-a', [string]$intent.action)
            }
            if ($intent.ContainsKey('dataUri') -and $intent.dataUri) {
                $args += @('-d', [string]$intent.dataUri)
            }
            if ($intent.ContainsKey('mimeType') -and $intent.mimeType) {
                $args += @('-t', [string]$intent.mimeType)
            }
            if ($intent.ContainsKey('component') -and $intent.component) {
                $args += @('-n', [string]$intent.component)
            }
            $args += @('-p', $package)
            Invoke-BrollAdb -Serial $Serial -Arguments $args -StepDescription "Launching $package via am start" -DryRun:$DryRun | Out-Null
            return
        }
    }

    Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'monkey', '-p', $package, '-c', 'android.intent.category.LAUNCHER', '1') -StepDescription "Launching $package via monkey" -DryRun:$DryRun | Out-Null
}

function Get-SettingsSummary {
    param([Parameter(Mandatory = $true)][hashtable]$Permutation)

    if ($Permutation.ContainsKey('label') -and $Permutation.label) {
        return [string]$Permutation.label
    }

    $parts = @()
    if ($Permutation.ContainsKey('id')) { $parts += [string]$Permutation.id }
    if ($Permutation.ContainsKey('overrides') -and $Permutation.overrides) {
        $overrides = ConvertTo-BrollHashtable -InputObject $Permutation.overrides
        if ($overrides.ContainsKey('retroarchCfg')) {
            $retro = ConvertTo-BrollHashtable -InputObject $overrides.retroarchCfg
            foreach ($k in @('video_driver', 'video_smooth', 'video_scale_integer')) {
                if ($retro.ContainsKey($k)) {
                    $parts += ("{0}={1}" -f $k, $retro[$k])
                }
            }
        }
    }
    if ($parts.Count -eq 0) {
        return 'settings'
    }
    return ($parts -join ', ')
}

Ensure-BrollCommand -Name 'adb'
Ensure-BrollCommand -Name 'scrcpy'

$matrixFullPath = Resolve-BrollPath -BasePath $PSScriptRoot -Path $MatrixPath
if (-not (Test-Path -LiteralPath $matrixFullPath)) {
    throw "Matrix file not found: $matrixFullPath"
}

$matrix = Get-Content -LiteralPath $matrixFullPath -Raw | ConvertFrom-Json
$matrixTable = ConvertTo-BrollHashtable -InputObject $matrix
if (-not $matrixTable.ContainsKey('target')) {
    throw 'Matrix must include target object.'
}
if (-not $matrixTable.ContainsKey('permutations')) {
    throw 'Matrix must include permutations array.'
}

$target = ConvertTo-BrollHashtable -InputObject $matrixTable.target
$emulator = [string]$target.emulator
if ([string]::IsNullOrWhiteSpace($emulator)) {
    throw 'target.emulator is required.'
}
$serialFromMatrix = ''
if ($matrixTable.ContainsKey('device') -and $matrixTable.device) {
    $device = ConvertTo-BrollHashtable -InputObject $matrixTable.device
    if ($device.ContainsKey('serial') -and $device.serial) {
        $serialFromMatrix = [string]$device.serial
    }
}
$serial = Resolve-BrollSerial -ExplicitSerial $DeviceSerial -MatrixSerial $serialFromMatrix
Write-BrollStatus -Message "Using adb serial: $serial"

$jobName = if ($matrixTable.ContainsKey('jobName') -and $matrixTable.jobName) { [string]$matrixTable.jobName } else { 'broll-job' }
$safeJobName = ConvertTo-BrollSafeName -Value $jobName
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$baseOutputRoot = if ($OutputRoot) {
    Resolve-BrollPath -BasePath $PSScriptRoot -Path $OutputRoot
}
elseif ($matrixTable.ContainsKey('outputRoot') -and $matrixTable.outputRoot) {
    Resolve-BrollPath -BasePath $PSScriptRoot -Path ([string]$matrixTable.outputRoot)
}
else {
    Resolve-BrollPath -BasePath $PSScriptRoot -Path '..\artifacts\broll'
}

$jobOutput = Join-Path $baseOutputRoot ("{0}-{1}" -f $safeJobName, $timestamp)
$clipsDir = Join-Path $jobOutput 'clips'
$manifestDir = Join-Path $jobOutput 'manifests'
$workDir = Join-Path $jobOutput '_work'
Ensure-BrollDirectory -Path $clipsDir
Ensure-BrollDirectory -Path $manifestDir
Ensure-BrollDirectory -Path $workDir

$durationSec = if ($matrixTable.ContainsKey('clipDurationSec')) { [int]$matrixTable.clipDurationSec } else { 12 }
if ($durationSec -lt 1) { throw 'clipDurationSec must be >= 1.' }

$startupDelaySec = if ($target.ContainsKey('startupDelaySec')) { [int]$target.startupDelaySec } else { 5 }
$gpuMetadata = Get-GpuMetadata -Serial $serial -DryRun:$DryRun
$captures = @()
$index = 0

# Device-safety discipline: the device must be returned to the state it was found in,
# no matter how the job ends. Any config file patched by a permutation gets backed up on
# its first patch (see ConfigPatcher's Backup-RemoteConfigFile) and restored here in the
# finally block below -- covering normal completion, thrown errors, and Ctrl+C alike.
try {
foreach ($rawPermutation in @($matrixTable.permutations)) {
    $index++
    $permutation = ConvertTo-BrollHashtable -InputObject $rawPermutation
    $permId = if ($permutation.ContainsKey('id') -and $permutation.id) { [string]$permutation.id } else { "perm$index" }
    $safePermId = ConvertTo-BrollSafeName -Value $permId
    $settingsSummary = Get-SettingsSummary -Permutation $permutation
    $clipFileName = "{0}_{1}_{2}.mp4" -f (ConvertTo-BrollSafeName -Value $emulator), $safePermId, $timestamp
    $clipPath = Join-Path $clipsDir $clipFileName
    $manifestPath = Join-Path $manifestDir ("{0}.manifest.json" -f $safePermId)

    Write-BrollStatus -Message "Processing permutation '$permId'"

    $context = @{
        Serial      = $serial
        WorkDir     = $workDir
        Target      = $target
        Permutation = $permutation
    }

    Invoke-ApplyEmulatorOverrides -Emulator $emulator -Context $context -DryRun:$DryRun
    Invoke-LaunchEmulator -Serial $serial -Target $target -DryRun:$DryRun
    if (-not $DryRun -and $startupDelaySec -gt 0) {
        Start-Sleep -Seconds $startupDelaySec
    }
    Invoke-PrepareEmulatorScene -Emulator $emulator -Context $context -DryRun:$DryRun

    $scrcpyArgs = @(
        '--serial', $serial,
        '--no-playback',
        '--no-window',
        '--time-limit', "$durationSec",
        '--record', $clipPath
    )
    if ($target.ContainsKey('scrcpyArgs') -and $target.scrcpyArgs) {
        foreach ($arg in @($target.scrcpyArgs)) {
            $scrcpyArgs += [string]$arg
        }
    }
    # scrcpy should self-terminate at --time-limit; add a generous buffer on top as a
    # backstop so a stalled recording (e.g. device disconnect mid-capture) can't hang the
    # whole job indefinitely.
    Invoke-BrollExternal -FilePath 'scrcpy' -Arguments $scrcpyArgs -StepDescription "Recording clip $clipFileName" -DryRun:$DryRun -TimeoutSec ($durationSec + 30) | Out-Null

    $manifest = [pscustomobject]@{
        timestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
        deviceSerial     = $serial
        emulator         = $emulator
        package          = [string]$target.package
        clipPath         = $clipPath
        clipFileName     = $clipFileName
        clipDurationSec  = $durationSec
        permutationId    = $permId
        settingsSummary  = $settingsSummary
        permutation      = $permutation
        gpuMetadata      = $gpuMetadata
        dryRun           = [bool]$DryRun
    }
    Write-BrollJson -Path $manifestPath -Object $manifest

    $captures += [pscustomobject]@{
        clipPath      = $clipPath
        manifestPath  = $manifestPath
        permutationId = $permId
        label         = $settingsSummary
    }
}
}
finally {
    $restoreContext = @{
        Serial      = $serial
        WorkDir     = $workDir
        Target      = $target
        Permutation = @{}
    }
    Write-BrollStatus -Message 'Restoring device config to pre-job state...'
    Invoke-RestoreEmulatorConfig -Emulator $emulator -Context $restoreContext -DryRun:$DryRun
}

$captureIndexPath = Join-Path $jobOutput 'captures-index.json'
$captureIndex = [pscustomobject]@{
    jobName      = $jobName
    matrixPath   = $matrixFullPath
    outputRoot   = $jobOutput
    emulator     = $emulator
    deviceSerial = $serial
    dryRun       = [bool]$DryRun
    captures     = $captures
}
Write-BrollJson -Path $captureIndexPath -Object $captureIndex
Write-BrollStatus -Message "Capture index written: $captureIndexPath"

return $captureIndex
