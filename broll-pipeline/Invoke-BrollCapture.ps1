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

function Ensure-BrollDeviceAwake {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [switch]$DryRun
    )

    if ($DryRun) { return }

    $power = Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'dumpsys', 'power') -StepDescription 'Checking device wakefulness' -AllowFailure
    $isAwake = $power.Output -match 'mWakefulness=Awake'
    if (-not $isAwake) {
        Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') -StepDescription 'Waking device screen' -AllowFailure | Out-Null
        Start-Sleep -Seconds 1
    }
    # Collapse the notification shade in case a stale shade/lockscreen overlay is stuck in focus.
    Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'cmd', 'statusbar', 'collapse') -StepDescription 'Collapsing notification shade' -AllowFailure | Out-Null
}

function Test-BrollForegroundPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Package
    )

    $focus = Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'dumpsys', 'window') -StepDescription 'Checking foreground focus' -AllowFailure
    $line = ($focus.Output -split "`r?`n") | Where-Object { $_ -match 'mCurrentFocus=' } | Select-Object -Last 1
    return ($line -and $line -like "*$Package*")
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
    Ensure-BrollDeviceAwake -Serial $Serial -DryRun:$DryRun
    Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'am', 'force-stop', $package) -StepDescription "Force-stopping $package" -DryRun:$DryRun | Out-Null

    # Only trust an explicit "am start" intent when it names a component, or an action that
    # already carries the LAUNCHER category. A bare action like MAIN with neither frequently
    # fails to resolve ("Error: Activity not started, unable to resolve Intent") and silently
    # no-ops, leaving whatever was already on screen in place (e.g. the home launcher) - which
    # would then get recorded as if it were the target app. In that ambiguous case, skip
    # straight to the monkey launcher fallback below, which reliably resolves via the
    # LAUNCHER category regardless of app internals.
    $hasReliableIntent = $false
    if ($Target.ContainsKey('launch') -and $Target.launch) {
        $launch = ConvertTo-BrollHashtable -InputObject $Target.launch
        if ($launch.ContainsKey('intent') -and $launch.intent) {
            $intent = ConvertTo-BrollHashtable -InputObject $launch.intent
            $hasComponent = $intent.ContainsKey('component') -and $intent.component
            $hasCategory = $intent.ContainsKey('category') -and $intent.category
            if ($hasComponent -or $hasCategory) {
                $args = @('shell', 'am', 'start')
                if ($intent.ContainsKey('action') -and $intent.action) {
                    $args += @('-a', [string]$intent.action)
                }
                if ($hasCategory) {
                    $args += @('-c', [string]$intent.category)
                }
                if ($intent.ContainsKey('dataUri') -and $intent.dataUri) {
                    $args += @('-d', [string]$intent.dataUri)
                }
                if ($intent.ContainsKey('mimeType') -and $intent.mimeType) {
                    $args += @('-t', [string]$intent.mimeType)
                }
                if ($hasComponent) {
                    $args += @('-n', [string]$intent.component)
                }
                $args += @('-p', $package)
                Invoke-BrollAdb -Serial $Serial -Arguments $args -StepDescription "Launching $package via am start" -DryRun:$DryRun | Out-Null
                $hasReliableIntent = $true
            }
        }
    }

    if (-not $hasReliableIntent) {
        Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'monkey', '-p', $package, '-c', 'android.intent.category.LAUNCHER', '1') -StepDescription "Launching $package via monkey" -DryRun:$DryRun | Out-Null
    }

    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        if (-not (Test-BrollForegroundPackage -Serial $Serial -Package $package)) {
            # One retry via the monkey fallback in case the configured intent path didn't take focus.
            Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'monkey', '-p', $package, '-c', 'android.intent.category.LAUNCHER', '1') -StepDescription "Launching $package via monkey (retry after launch did not take focus)" -AllowFailure | Out-Null
            Start-Sleep -Seconds 2
            if (-not (Test-BrollForegroundPackage -Serial $Serial -Package $package)) {
                Write-Warning "Launch verification failed: $package is not the foreground focus after launch attempts. The recorded clip may not show the target app."
            }
        }
    }
}

function Invoke-BrollGameplaySequence {
    # Drives real gameplay input via the RD-Gauntlet virtual-gamepad module (adb shell
    # uinput) so a comparison clip can show actual driven motion instead of a static
    # menu/save-state screen. Non-fatal by design: a hiccup here should degrade the clip
    # (less motion than intended), not abort the whole capture job or skip the
    # device-restore safety net in the caller's finally block.
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [switch]$DryRun
    )

    if (-not ($Target.ContainsKey('gameplaySequence') -and $Target.gameplaySequence)) {
        return
    }

    $seq = ConvertTo-BrollHashtable -InputObject $Target.gameplaySequence
    $seqType = if ($seq.ContainsKey('type')) { [string]$seq.type } else { '' }
    if ($seqType -ne 'virtual_gamepad_sequence') {
        Write-BrollStatus -Message "Unknown gameplaySequence.type '$seqType'; skipping." -IsWarning
        return
    }
    if (-not ($seq.ContainsKey('sequenceFile') -and $seq.sequenceFile)) {
        throw 'gameplaySequence.sequenceFile is required for type virtual_gamepad_sequence.'
    }

    $sequenceFile = Resolve-BrollPath -BasePath $PSScriptRoot -Path ([string]$seq.sequenceFile)
    if (-not (Test-Path -LiteralPath $sequenceFile)) {
        throw "Gameplay sequence file not found: $sequenceFile"
    }

    $vgpScript = Resolve-BrollPath -BasePath $PSScriptRoot -Path '..\virtual-gamepad\rdg_virtual_gamepad.py'
    $timeoutSec = if ($seq.ContainsKey('timeoutSec')) { [int]$seq.timeoutSec } else { 20 }

    $pyArgs = @($vgpScript, 'press-sequence', '--serial', $Serial, '--sequence-file', $sequenceFile)
    $result = Invoke-BrollExternal -FilePath 'python' -Arguments $pyArgs -StepDescription 'Driving gameplay via virtual gamepad' -DryRun:$DryRun -AllowFailure -TimeoutSec $timeoutSec
    if (-not $DryRun -and $result.ExitCode -ne 0) {
        Write-BrollStatus -Message "Virtual gamepad sequence exited with code $($result.ExitCode); clip may show less motion than intended.`n$($result.Output)" -IsWarning
    }
}

function Invoke-BrollRecordClip {
    # Records the clip with scrcpy while concurrently driving the (optional) gameplay
    # sequence, so scripted input actually happens *during* the recording window instead
    # of before/after it. Mirrors Invoke-BrollExternal's timeout/force-kill safety
    # semantics but can't reuse it directly since that helper blocks until the child
    # process exits, which would prevent anything from running concurrently with scrcpy.
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string[]]$ScrcpyArgs,
        [Parameter(Mandatory = $true)][string]$ClipFileName,
        [Parameter(Mandatory = $true)][int]$DurationSec,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [switch]$DryRun
    )

    $joined = ($ScrcpyArgs | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' '
    Write-BrollStatus -Message "Recording clip $ClipFileName`: scrcpy $joined"

    if ($DryRun) {
        Invoke-BrollGameplaySequence -Serial $Serial -Target $Target -DryRun
        return
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'scrcpy'
    foreach ($arg in $ScrcpyArgs) { $psi.ArgumentList.Add($arg) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $stdout = [System.Text.StringBuilder]::new()
    $stderr = [System.Text.StringBuilder]::new()
    $outEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action { if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data).Append([Environment]::NewLine) | Out-Null } } -MessageData $stdout
    $errEvent = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action { if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data).Append([Environment]::NewLine) | Out-Null } } -MessageData $stderr

    $timedOut = $false
    try {
        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()

        # Give scrcpy a moment to actually attach and start writing frames before driving
        # any scripted input -- otherwise the first gameplay actions could land before the
        # recording has actually started.
        Start-Sleep -Seconds 2

        Invoke-BrollGameplaySequence -Serial $Serial -Target $Target

        $timedOut = -not $proc.WaitForExit(($DurationSec + 30) * 1000)
        if ($timedOut) {
            Write-BrollStatus -Message "Recording clip $ClipFileName exceeded $($DurationSec + 30)s timeout; force-killing scrcpy." -IsWarning
            try { $proc.Kill($true) } catch { }
            $proc.WaitForExit(5000) | Out-Null
        }
        else {
            $proc.WaitForExit()
        }
    }
    finally {
        Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Job $outEvent -Force -ErrorAction SilentlyContinue
        Remove-Job -Job $errEvent -Force -ErrorAction SilentlyContinue
    }

    $exitCode = if ($timedOut) { -1 } else { $proc.ExitCode }
    if (($exitCode -ne 0) -and ($exitCode -ne -1)) {
        $text = ($stdout.ToString() + $stderr.ToString())
        Write-BrollStatus -Message "scrcpy exited with code $exitCode for clip $ClipFileName. Output:`n$text" -IsWarning
    }
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
    # scrcpy should self-terminate at --time-limit; a generous buffer on top acts as a
    # backstop so a stalled recording (e.g. device disconnect mid-capture) can't hang the
    # whole job indefinitely. Recording and any configured gameplay-driving sequence run
    # concurrently so the clip actually shows the driven motion, not a static screen.
    Invoke-BrollRecordClip -Serial $serial -ScrcpyArgs $scrcpyArgs -ClipFileName $clipFileName -DurationSec $durationSec -Target $target -DryRun:$DryRun

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
        gameplaySequence = if ($target.ContainsKey('gameplaySequence')) { $target.gameplaySequence } else { $null }
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
