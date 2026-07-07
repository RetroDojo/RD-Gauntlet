[CmdletBinding()]
param(
    [string]$DeviceName,
    [string]$AppsConfig = ".\apps.json",
    [string]$OutDir,
    [switch]$SkipMonkey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Append-Utf8NoBomLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Line
    )

    [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    $json = ConvertTo-Json -InputObject $Object -Depth 10
    Write-Utf8NoBomFile -Path $Path -Content $json
}

function Resolve-SuitePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

function Get-SafeName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = $Value -replace '[^A-Za-z0-9._-]+', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'item'
    }

    return $safe
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$ErrorsLog,
        [switch]$IsError
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] {1}" -f $timestamp, $Message
    if ($IsError) {
        Write-Warning $Message
        if ($ErrorsLog) {
            Append-Utf8NoBomLine -Path $ErrorsLog -Line $line
        }
    }
    else {
        Write-Host $line
    }
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StepDescription = 'adb command',
        [switch]$AllowFailure
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & adb @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw ("{0} failed with exit code {1}. Args: adb {2}`n{3}" -f $StepDescription, $exitCode, ($Arguments -join ' '), $text)
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $text
    }
}

function Get-ConnectedDeviceSerials {
    $result = Invoke-Adb -Arguments @('devices') -StepDescription 'Enumerating adb devices'
    $serials = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ($line -match '^(?<serial>\S+)\s+device$') {
            $serials += $Matches.serial
        }
    }

    return $serials
}

function Resolve-TargetDevice {
    param(
        [Parameter(Mandatory = $true)][string]$DevicesConfigPath,
        [string]$RequestedName
    )

    $devices = @()
    if (Test-Path -LiteralPath $DevicesConfigPath) {
        $loaded = Get-Content -LiteralPath $DevicesConfigPath -Raw | ConvertFrom-Json
        if ($loaded) {
            $devices = @($loaded | ForEach-Object { $_ })
        }
    }

    $connectedSerials = @(Get-ConnectedDeviceSerials)
    $selected = $null

    if ($RequestedName) {
        $selected = $devices | Where-Object { $_.name -eq $RequestedName } | Select-Object -First 1
        if (-not $selected) {
            throw "Device name '$RequestedName' was not found in $DevicesConfigPath."
        }
    }
    elseif ($connectedSerials.Count -eq 1) {
        $selected = $devices | Where-Object { $_.adbSerial -eq $connectedSerials[0] } | Select-Object -First 1
    }
    elseif ($connectedSerials.Count -eq 0) {
        throw "No adb devices are connected. Connect a device or specify a configured -DeviceName with a reachable adbSerial."
    }
    else {
        throw "Multiple adb devices are connected ($($connectedSerials -join ', ')). Use -DeviceName or populate adbSerial in devices.json."
    }

    if ($selected) {
        $serial = $selected.adbSerial
        if ([string]::IsNullOrWhiteSpace($serial)) {
            if ($connectedSerials.Count -ne 1) {
                throw "Device '$($selected.name)' has no adbSerial configured and auto-detect requires exactly one connected device."
            }
            $serial = $connectedSerials[0]
        }

        if ($connectedSerials -notcontains $serial) {
            throw "Configured device '$($selected.name)' expects serial '$serial', but it is not currently connected."
        }

        return [pscustomobject]@{
            Name      = $selected.name
            AdbSerial = $serial
            Notes     = $selected.notes
            Settings  = $selected
        }
    }

    return [pscustomobject]@{
        Name      = $connectedSerials[0]
        AdbSerial = $connectedSerials[0]
        Notes     = 'Auto-detected device (not present in devices.json).'
        Settings  = [pscustomobject]@{}
    }
}

function Get-ConfigBool {
    param(
        [Parameter(Mandatory = $false)]$App,
        [Parameter(Mandatory = $false)]$DeviceSettings,
        [Parameter(Mandatory = $true)][string]$AppProperty,
        [Parameter(Mandatory = $true)][string]$DeviceProperty,
        [bool]$Default = $false
    )

    if ($App) {
        $prop = $App.PSObject.Properties[$AppProperty]
        if ($prop -and $null -ne $prop.Value) {
            return [bool]$prop.Value
        }
    }
    if ($DeviceSettings) {
        $prop = $DeviceSettings.PSObject.Properties[$DeviceProperty]
        if ($prop -and $null -ne $prop.Value) {
            return [bool]$prop.Value
        }
    }
    return $Default
}

function Ensure-TelemetryMonitor {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$LocalScriptPath
    )

    $remotePath = '/data/local/tmp/telemetry-monitor.sh'
    $check = Invoke-Adb -Arguments @('-s', $Serial, 'shell', "[ -f $remotePath ] && echo yes") -StepDescription 'Checking telemetry monitor presence'
    if ($check.Output -notmatch '\byes\b') {
        Invoke-Adb -Arguments @('-s', $Serial, 'push', $LocalScriptPath, $remotePath) -StepDescription 'Pushing telemetry monitor' | Out-Null
    }

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'chmod', '755', $remotePath) -StepDescription 'Chmod telemetry monitor' | Out-Null
}

function Ensure-RemoteScript {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$LocalScriptPath,
        [Parameter(Mandatory = $true)][string]$RemoteScriptPath
    )

    Invoke-Adb -Arguments @('-s', $Serial, 'push', $LocalScriptPath, $RemoteScriptPath) -StepDescription "Pushing script $(Split-Path -Leaf $LocalScriptPath)" | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'chmod', '755', $RemoteScriptPath) -StepDescription "Chmod $RemoteScriptPath" | Out-Null
}

function Start-RemoteTelemetry {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$RemoteCsv
    )

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', "nohup sh /data/local/tmp/telemetry-monitor.sh $RemoteCsv 2 > /dev/null 2>&1 &") -StepDescription "Starting telemetry -> $RemoteCsv" | Out-Null
}

function Stop-RemoteTelemetry {
    param([Parameter(Mandatory = $true)][string]$Serial)
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pkill', '-f', 'telemetry-monitor.sh') -StepDescription 'Stopping telemetry monitor' -AllowFailure | Out-Null
}

function Stop-RemoteMonkey {
    param([Parameter(Mandatory = $true)][string]$Serial)
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pkill', '-f', 'com.android.commands.monkey') -StepDescription 'Stopping monkey' -AllowFailure | Out-Null
}

function Capture-Screenshot {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $remotePath = '/sdcard/benchsuite_screencap.png'
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'screencap', '-p', $remotePath) -StepDescription 'Capturing screenshot on device' | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'pull', $remotePath, $LocalPath) -StepDescription "Pulling screenshot to $LocalPath" | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'rm', '-f', $remotePath) -StepDescription 'Cleaning remote screenshot temp' -AllowFailure | Out-Null
}

function Save-AdbShellOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$ShellCommand,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [switch]$AllowFailure
    )

    $result = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $ShellCommand) -StepDescription $ShellCommand -AllowFailure:$AllowFailure
    Write-Utf8NoBomFile -Path $LocalPath -Content $result.Output
    return $result
}

function Wait-WithCountdown {
    param(
        [Parameter(Mandatory = $true)][int]$DurationSec,
        [Parameter(Mandatory = $true)][string]$MessagePrefix
    )

    $remaining = $DurationSec
    while ($remaining -gt 0) {
        Write-Host ("{0}: {1}s remaining" -f $MessagePrefix, $remaining)
        $sleepFor = [Math]::Min(30, $remaining)
        Start-Sleep -Seconds $sleepFor
        $remaining -= $sleepFor
    }
}

function Read-TrimmedProp {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$ShellCommand
    )

    $result = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $ShellCommand) -StepDescription $ShellCommand
    return $result.Output.Trim()
}

function Get-BatteryLevelLine {
    param([Parameter(Mandatory = $true)][string]$Serial)

    $batteryDump = Read-TrimmedProp -Serial $Serial -ShellCommand 'dumpsys battery'
    $line = ($batteryDump -split "`r?`n" | Where-Object { $_ -match '^\s*level:' } | Select-Object -First 1)
    if ($line) {
        return $line.Trim()
    }

    return ''
}

function Invoke-RemoteJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$RemoteCommand,
        [Parameter(Mandatory = $true)][string]$LocalOutputPath,
        [switch]$AllowFailure
    )

    $result = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $RemoteCommand) -StepDescription $RemoteCommand -AllowFailure:$AllowFailure
    $content = $result.Output.Trim()
    if ([string]::IsNullOrWhiteSpace($content)) {
        $content = '{"status":"error","error":"empty_output"}'
    }
    Write-Utf8NoBomFile -Path $LocalOutputPath -Content $content
    return $result
}

function Get-StickAxisRanges {
    param([Parameter(Mandatory = $true)][string]$GeteventInfoText)

    $devices = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in ($GeteventInfoText -split "`r?`n")) {
        if ($line -match '^add device \d+:\s+(?<node>/dev/input/event\d+)') {
            if ($current) { $devices.Add($current) }
            $current = [ordered]@{
                Node  = $Matches.node
                Axes  = @{}
            }
            continue
        }
        if (-not $current) { continue }
        if ($line -match '^\s*ABS_(?<axis>X|Y|RX|RY)\s*:\s*value\s+\d+,\s*min\s+(?<min>-?\d+),\s*max\s+(?<max>-?\d+)') {
            $current.Axes["ABS_$($Matches.axis)"] = [ordered]@{
                Min = [int]$Matches.min
                Max = [int]$Matches.max
            }
        }
    }
    if ($current) { $devices.Add($current) }
    return $devices
}

function Invoke-StickDriftCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$LocalOutputPath,
        [int]$DurationSec = 10
    )

    Write-Host "DO NOT TOUCH THE CONTROLLER - sampling idle drift for $DurationSec seconds..."
    for ($i = 3; $i -ge 1; $i--) {
        Write-Host ("Starting in {0}..." -f $i)
        Start-Sleep -Seconds 1
    }

    $info = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'getevent', '-pl') -StepDescription 'Enumerating input devices'
    $candidates = Get-StickAxisRanges -GeteventInfoText $info.Output
    $target = $candidates | Where-Object { $_.Axes.ContainsKey('ABS_X') -and $_.Axes.ContainsKey('ABS_Y') } | Select-Object -First 1

    if (-not $target) {
        Write-Utf8NoBomFile -Path $LocalOutputPath -Content '{"status":"unsupported","reason":"no_abs_stick_device_found"}'
        return
    }

    $node = [string]$target.Node
    $captureCmd = "getevent -lt $node > /data/local/tmp/stick_drift_raw.txt 2>/dev/null & pid=\$!; sleep $DurationSec; kill -INT \$pid >/dev/null 2>&1; wait \$pid >/dev/null 2>&1; cat /data/local/tmp/stick_drift_raw.txt; rm -f /data/local/tmp/stick_drift_raw.txt"
    $raw = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $captureCmd) -StepDescription "Sampling $node idle events"

    $axisCodeToName = @{
        '0000' = 'ABS_X'
        '0001' = 'ABS_Y'
        '0003' = 'ABS_RX'
        '0004' = 'ABS_RY'
    }
    $samples = @{
        ABS_X  = New-Object System.Collections.Generic.List[int]
        ABS_Y  = New-Object System.Collections.Generic.List[int]
        ABS_RX = New-Object System.Collections.Generic.List[int]
        ABS_RY = New-Object System.Collections.Generic.List[int]
    }

    foreach ($line in ($raw.Output -split "`r?`n")) {
        if ($line -match ':\s+0003\s+(?<code>[0-9a-fA-F]{4})\s+(?<value>[0-9a-fA-F]{8})') {
            $code = $Matches.code.ToLowerInvariant()
            if ($axisCodeToName.ContainsKey($code)) {
                $axis = $axisCodeToName[$code]
                [void]$samples[$axis].Add([Convert]::ToInt32($Matches.value, 16))
            }
        }
    }

    $axisResults = @()
    foreach ($axis in @('ABS_X', 'ABS_Y', 'ABS_RX', 'ABS_RY')) {
        if (-not $target.Axes.ContainsKey($axis)) { continue }
        $range = $target.Axes[$axis]
        $center = [math]::Round(($range.Min + $range.Max) / 2.0, 0)
        $span = [math]::Max(1, $range.Max - $range.Min)
        $threshold = [math]::Max(4, [math]::Round($span * 0.03, 0))
        $vals = $samples[$axis]
        if ($vals.Count -eq 0) {
            $axisResults += [pscustomobject]@{
                axis = $axis; sampleCount = 0; center = $center; maxDeviation = $null; threshold = $threshold; drift = $null
            }
            continue
        }
        $maxDev = 0
        foreach ($v in $vals) {
            $dev = [math]::Abs($v - $center)
            if ($dev -gt $maxDev) { $maxDev = $dev }
        }
        $axisResults += [pscustomobject]@{
            axis = $axis
            sampleCount = $vals.Count
            center = [int]$center
            maxDeviation = [int]$maxDev
            threshold = [int]$threshold
            drift = ($maxDev -gt $threshold)
        }
    }

    $hasDrift = $axisResults | Where-Object { $_.drift -eq $true } | Select-Object -First 1
    $out = [ordered]@{
        status = 'ok'
        node = $node
        durationSec = $DurationSec
        thresholdRule = 'max(4, 3% of axis span)'
        pass = (-not $hasDrift)
        axes = $axisResults
    }
    Write-JsonFile -Path $LocalOutputPath -Object $out
}

function Invoke-PerfettoPrototype {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Package,
        [Parameter(Mandatory = $true)][string]$AppDir,
        [int]$DurationSec = 15
    )

    $traceRemote = "/data/misc/perfetto-traces/perfetto_${Package}_fps.perfetto-trace"
    $traceLocal = Join-Path $AppDir 'perfetto-trace.perfetto-trace'
    $kvLocal = Join-Path $AppDir 'perfetto-capture.txt'
    $jsonLocal = Join-Path $AppDir 'perfetto-fps.json'
    $remoteScript = '/data/local/tmp/perfetto-surfaceview-fps.sh'
    $command = "sh $remoteScript $Package $DurationSec $traceRemote"

    $capture = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $command) -StepDescription "Perfetto capture for $Package" -AllowFailure
    Write-Utf8NoBomFile -Path $kvLocal -Content $capture.Output

    if ($capture.ExitCode -ne 0) {
        Write-JsonFile -Path $jsonLocal -Object ([ordered]@{
                status = 'error'
                package = $Package
                note = "Perfetto capture command failed (exit $($capture.ExitCode))."
            })
        return
    }

    try {
        Invoke-Adb -Arguments @('-s', $Serial, 'pull', $traceRemote, $traceLocal) -StepDescription "Pulling perfetto trace for $Package" | Out-Null
    }
    catch {
        Write-JsonFile -Path $jsonLocal -Object ([ordered]@{
                status = 'error'
                package = $Package
                note = "Trace pull failed: $($_.Exception.Message)"
            })
        return
    }

    $parserPath = Resolve-SuitePath -Path '.\Parse-PerfettoSurfaceFps.py'
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $parserOutput = & python $parserPath $traceLocal $Package $jsonLocal 2>&1
    }
    finally {
        $ErrorActionPreference = $oldEap
    }

    if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $jsonLocal)) {
        Write-JsonFile -Path $jsonLocal -Object ([ordered]@{
                status = 'error'
                package = $Package
                note = "Perfetto parser failed: $($parserOutput -join ' ')"
            })
    }

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'rm', '-f', $traceRemote) -StepDescription 'Cleaning remote perfetto trace' -AllowFailure | Out-Null
}

$devicesConfigPath = Resolve-SuitePath -Path '.\devices.json'
$appsConfigPath = Resolve-SuitePath -Path $AppsConfig
$telemetryLocalPath = Resolve-SuitePath -Path '.\telemetry-monitor.sh'
$reportScriptPath = Resolve-SuitePath -Path '.\New-BenchReport.ps1'
$storageTestLocalPath = Resolve-SuitePath -Path '.\storage-speed-test.sh'
$wifiTestLocalPath = Resolve-SuitePath -Path '.\wifi-throughput-test.sh'
$hapticsTestLocalPath = Resolve-SuitePath -Path '.\haptic-intensity-check.sh'
$perfettoLocalPath = Resolve-SuitePath -Path '.\perfetto-surfaceview-fps.sh'
$perfettoParserPath = Resolve-SuitePath -Path '.\Parse-PerfettoSurfaceFps.py'

if (-not (Test-Path -LiteralPath $appsConfigPath)) {
    throw "Apps config not found: $appsConfigPath"
}
if (-not (Test-Path -LiteralPath $telemetryLocalPath)) {
    throw "telemetry-monitor.sh not found: $telemetryLocalPath"
}
if (-not (Test-Path -LiteralPath $reportScriptPath)) {
    throw "Report script not found: $reportScriptPath"
}
foreach ($path in @($storageTestLocalPath, $wifiTestLocalPath, $hapticsTestLocalPath, $perfettoLocalPath, $perfettoParserPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required helper file not found: $path"
    }
}

$targetDevice = Resolve-TargetDevice -DevicesConfigPath $devicesConfigPath -RequestedName $DeviceName
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $PSScriptRoot ("results\{0}\{1}" -f $timestamp, (Get-SafeName -Value $targetDevice.Name))
}
$resolvedOutDir = Resolve-SuitePath -Path $OutDir
New-Item -ItemType Directory -Path $resolvedOutDir -Force | Out-Null
$errorsLog = Join-Path $resolvedOutDir 'errors.log'
Write-Utf8NoBomFile -Path $errorsLog -Content ''

$appsLoaded = Get-Content -LiteralPath $appsConfigPath -Raw | ConvertFrom-Json
$apps = @($appsLoaded | ForEach-Object { $_ })
if ($apps.Count -eq 0) {
    throw "Apps config '$appsConfigPath' contains no app entries."
}

$needPerfettoParser = $false
foreach ($a in $apps) {
    if (Get-ConfigBool -App $a -DeviceSettings $null -AppProperty 'capturePerfetto' -DeviceProperty 'capturePerfetto' -Default $false) {
        $needPerfettoParser = $true
        break
    }
}
if ((-not $needPerfettoParser) -and (Get-ConfigBool -App $null -DeviceSettings $targetDevice.Settings -AppProperty 'capturePerfetto' -DeviceProperty 'capturePerfetto' -Default $false)) {
    $needPerfettoParser = $true
}

if ($needPerfettoParser) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & python -c "import perfetto.trace_processor" 2>$null
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Status -Message 'Installing python perfetto package for trace parsing...'
        & python -m pip install --quiet perfetto
    }
}

Write-Status -Message ("Using device '{0}' ({1})" -f $targetDevice.Name, $targetDevice.AdbSerial)
Ensure-TelemetryMonitor -Serial $targetDevice.AdbSerial -LocalScriptPath $telemetryLocalPath
Ensure-RemoteScript -Serial $targetDevice.AdbSerial -LocalScriptPath $storageTestLocalPath -RemoteScriptPath '/data/local/tmp/storage-speed-test.sh'
Ensure-RemoteScript -Serial $targetDevice.AdbSerial -LocalScriptPath $wifiTestLocalPath -RemoteScriptPath '/data/local/tmp/wifi-throughput-test.sh'
Ensure-RemoteScript -Serial $targetDevice.AdbSerial -LocalScriptPath $hapticsTestLocalPath -RemoteScriptPath '/data/local/tmp/haptic-intensity-check.sh'
Ensure-RemoteScript -Serial $targetDevice.AdbSerial -LocalScriptPath $perfettoLocalPath -RemoteScriptPath '/data/local/tmp/perfetto-surfaceview-fps.sh'

$deviceInfo = [ordered]@{
    suiteStartedAt       = (Get-Date).ToString('o')
    configuredName       = $targetDevice.Name
    adbSerial            = $targetDevice.AdbSerial
    notes                = $targetDevice.Notes
    productModel         = Read-TrimmedProp -Serial $targetDevice.AdbSerial -ShellCommand 'getprop ro.product.model'
    androidRelease       = Read-TrimmedProp -Serial $targetDevice.AdbSerial -ShellCommand 'getprop ro.build.version.release'
    buildFingerprint     = Read-TrimmedProp -Serial $targetDevice.AdbSerial -ShellCommand 'getprop ro.build.fingerprint'
    wmSize               = Read-TrimmedProp -Serial $targetDevice.AdbSerial -ShellCommand 'wm size'
    baselineBatteryLevel = Get-BatteryLevelLine -Serial $targetDevice.AdbSerial
}

Write-JsonFile -Path (Join-Path $resolvedOutDir 'device-info.json') -Object $deviceInfo
Write-JsonFile -Path (Join-Path $resolvedOutDir 'apps-used.json') -Object $apps
Write-Utf8NoBomFile -Path (Join-Path $resolvedOutDir 'suite-notes.txt') -Content @"
Device: $($targetDevice.Name)
Serial: $($targetDevice.AdbSerial)
SkipMonkey: $($SkipMonkey.IsPresent)
AppsConfig: $appsConfigPath
Telemetry interval: 2 seconds
"@

$runStickDriftSuite = Get-ConfigBool -DeviceSettings $targetDevice.Settings -App $null -AppProperty 'checkStickDrift' -DeviceProperty 'checkStickDrift' -Default $false
$runHapticsSuite = Get-ConfigBool -DeviceSettings $targetDevice.Settings -App $null -AppProperty 'sampleHaptics' -DeviceProperty 'sampleHaptics' -Default $false

if ($runStickDriftSuite) {
    try {
        Invoke-StickDriftCheck -Serial $targetDevice.AdbSerial -LocalOutputPath (Join-Path $resolvedOutDir 'stick-drift.json') -DurationSec 10
    }
    catch {
        Write-Status -Message ("Stick drift check failed: {0}" -f $_.Exception.Message) -ErrorsLog $errorsLog -IsError
    }
}

if ($runHapticsSuite) {
    try {
        Invoke-RemoteJsonScript -Serial $targetDevice.AdbSerial -RemoteCommand 'sh /data/local/tmp/haptic-intensity-check.sh' -LocalOutputPath (Join-Path $resolvedOutDir 'haptic-intensity.json') -AllowFailure | Out-Null
    }
    catch {
        Write-Status -Message ("Haptic intensity check failed: {0}" -f $_.Exception.Message) -ErrorsLog $errorsLog -IsError
    }
}

foreach ($app in $apps) {
    $appName = [string]$app.name
    $package = [string]$app.package
    $durationSec = [int]$app.durationSec
    $monkeyEnabled = [bool]$app.monkeyEnabled
    $pctTouch = if ($app.PSObject.Properties['monkeyPctTouch'] -and $null -ne $app.monkeyPctTouch) { [int]$app.monkeyPctTouch } else { 70 }
    $pctMotion = if ($app.PSObject.Properties['monkeyPctMotion'] -and $null -ne $app.monkeyPctMotion) { [int]$app.monkeyPctMotion } else { 20 }
    $captureStorageSpeed = Get-ConfigBool -App $app -DeviceSettings $targetDevice.Settings -AppProperty 'captureStorageSpeed' -DeviceProperty 'captureStorageSpeed' -Default $false
    $captureWifiThroughput = Get-ConfigBool -App $app -DeviceSettings $targetDevice.Settings -AppProperty 'captureWifiThroughput' -DeviceProperty 'captureWifiThroughput' -Default $false
    $capturePerfetto = Get-ConfigBool -App $app -DeviceSettings $targetDevice.Settings -AppProperty 'capturePerfetto' -DeviceProperty 'capturePerfetto' -Default $false
    $perfettoDurationSec = if ($app.PSObject.Properties['perfettoDurationSec'] -and $null -ne $app.perfettoDurationSec) { [int]$app.perfettoDurationSec } elseif ($targetDevice.Settings.PSObject.Properties['perfettoDurationSec'] -and $null -ne $targetDevice.Settings.perfettoDurationSec) { [int]$targetDevice.Settings.perfettoDurationSec } else { 15 }
    $safeAppName = Get-SafeName -Value $appName
    $appDir = Join-Path $resolvedOutDir $safeAppName
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null

    $telemetryRemote = "/sdcard/telemetry_{0}.csv" -f $safeAppName
    $cooldownRemote = "/sdcard/cooldown_{0}.csv" -f $safeAppName
    $telemetryLocal = Join-Path $appDir 'telemetry.csv'
    $cooldownLocal = Join-Path $appDir 'cooldown.csv'
    $launchShot = Join-Path $appDir '00-launch.png'
    $endShot = Join-Path $appDir '99-end.png'
    $framestatsPath = Join-Path $appDir 'framestats.txt'
    $batterystatsPath = Join-Path $appDir 'batterystats.txt'
    $batterySnapshotPath = Join-Path $appDir 'battery-snapshot.txt'
    $appMetaPath = Join-Path $appDir 'app-metadata.json'
    $monkeyProcess = $null

    Write-JsonFile -Path $appMetaPath -Object ([ordered]@{
            name            = $appName
            package         = $package
            type            = $app.type
            durationSec     = $durationSec
            monkeyEnabled   = $monkeyEnabled
            monkeyPctTouch  = $pctTouch
            monkeyPctMotion = $pctMotion
            captureStorageSpeed = $captureStorageSpeed
            captureWifiThroughput = $captureWifiThroughput
            capturePerfetto = $capturePerfetto
            perfettoDurationSec = $perfettoDurationSec
            notes           = $app.notes
            skipMonkey      = $SkipMonkey.IsPresent
        })

    Write-Status -Message ("Starting app '{0}' ({1})" -f $appName, $package)

    try {
        $packageCheck = Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'shell', 'pm', 'path', $package) -StepDescription "Checking package $package" -AllowFailure
        if ($packageCheck.Output -notmatch '^package:') {
            throw "Package '$package' is not installed or not visible to pm path."
        }

        Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'shell', 'am', 'force-stop', $package) -StepDescription "Force-stopping $package before launch" -AllowFailure | Out-Null
        Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'shell', 'monkey', '-p', $package, '-c', 'android.intent.category.LAUNCHER', '1') -StepDescription "Launching $package" | Out-Null
        Start-Sleep -Seconds 4

        try {
            Capture-Screenshot -Serial $targetDevice.AdbSerial -LocalPath $launchShot
        }
        catch {
            Write-Status -Message ("Launch screenshot failed for {0}: {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'shell', 'rm', '-f', $telemetryRemote, $cooldownRemote) -StepDescription 'Cleaning prior telemetry CSVs' -AllowFailure | Out-Null
        Start-RemoteTelemetry -Serial $targetDevice.AdbSerial -RemoteCsv $telemetryRemote
        Start-Sleep -Seconds 2

        if ((-not $SkipMonkey.IsPresent) -and $monkeyEnabled) {
            if (([string]$app.type) -eq 'benchmark') {
                Write-Status -Message ("Monkey is enabled for benchmark '{0}', but it will not reliably trigger the official benchmark flow. Use -SkipMonkey when you want to drive the app manually." -f $appName)
            }

            $monkeyArgs = @(
                '-s', $targetDevice.AdbSerial,
                'shell', 'monkey',
                '-p', $package,
                '--pct-touch', $pctTouch.ToString(),
                '--pct-motion', $pctMotion.ToString(),
                '--pct-appswitch', '0',
                '--pct-syskeys', '0',
                '--throttle', '50',
                '--ignore-crashes',
                '--ignore-timeouts',
                '--ignore-security-exceptions',
                '-v', '5000'
            )

            $monkeyProcess = Start-Process -FilePath 'adb' -ArgumentList $monkeyArgs -WindowStyle Hidden -PassThru
            Wait-WithCountdown -DurationSec $durationSec -MessagePrefix ("Monkey run for {0}" -f $appName)
        }
        else {
            Write-Status -Message ("Manual interaction window for '{0}': {1}s. Telemetry is running; drive the benchmark/app yourself." -f $appName, $durationSec)
            Wait-WithCountdown -DurationSec $durationSec -MessagePrefix ("Manual window for {0}" -f $appName)
        }

        if ($capturePerfetto) {
            Write-Status -Message ("Capturing Perfetto prototype trace for '{0}' ({1}s)." -f $appName, $perfettoDurationSec)
            Invoke-PerfettoPrototype -Serial $targetDevice.AdbSerial -Package $package -AppDir $appDir -DurationSec $perfettoDurationSec
        }

        # framestats can be sparse or summary-only depending on Android version/app renderer; capture best-effort and parse later.
        Save-AdbShellOutput -Serial $targetDevice.AdbSerial -ShellCommand "dumpsys gfxinfo $package framestats" -LocalPath $framestatsPath -AllowFailure | Out-Null
        # On non-privileged / unrooted builds this per-app batterystats output may be limited or empty; keep it non-fatal.
        Save-AdbShellOutput -Serial $targetDevice.AdbSerial -ShellCommand "dumpsys batterystats --charged $package" -LocalPath $batterystatsPath -AllowFailure | Out-Null
        Save-AdbShellOutput -Serial $targetDevice.AdbSerial -ShellCommand 'dumpsys battery' -LocalPath $batterySnapshotPath -AllowFailure | Out-Null
    }
    catch {
        Write-Status -Message ("App '{0}' failed during main run: {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
    }
    finally {
        try {
            Stop-RemoteMonkey -Serial $targetDevice.AdbSerial
        }
        catch {
            Write-Status -Message ("Monkey stop warning for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        if ($monkeyProcess) {
            try {
                if (-not $monkeyProcess.HasExited) {
                    Stop-Process -Id $monkeyProcess.Id -Force
                }
            }
            catch {
            }
        }

        try {
            Stop-RemoteTelemetry -Serial $targetDevice.AdbSerial
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Status -Message ("Telemetry stop warning for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        try {
            Capture-Screenshot -Serial $targetDevice.AdbSerial -LocalPath $endShot
        }
        catch {
            Write-Status -Message ("End screenshot failed for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        try {
            Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'pull', $telemetryRemote, $telemetryLocal) -StepDescription "Pulling telemetry for $appName" | Out-Null
        }
        catch {
            Write-Status -Message ("Telemetry pull failed for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        try {
            Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'shell', 'am', 'force-stop', $package) -StepDescription "Force-stopping $package after run" -AllowFailure | Out-Null
        }
        catch {
            Write-Status -Message ("Post-run force-stop warning for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        try {
            Start-RemoteTelemetry -Serial $targetDevice.AdbSerial -RemoteCsv $cooldownRemote
            Wait-WithCountdown -DurationSec 15 -MessagePrefix ("Cooldown for {0}" -f $appName)
            Stop-RemoteTelemetry -Serial $targetDevice.AdbSerial
            Start-Sleep -Seconds 2
            Invoke-Adb -Arguments @('-s', $targetDevice.AdbSerial, 'pull', $cooldownRemote, $cooldownLocal) -StepDescription "Pulling cooldown telemetry for $appName" | Out-Null
        }
        catch {
            Write-Status -Message ("Cooldown capture failed for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
        }

        if ($captureStorageSpeed) {
            try {
                Invoke-RemoteJsonScript -Serial $targetDevice.AdbSerial -RemoteCommand 'sh /data/local/tmp/storage-speed-test.sh 100' -LocalOutputPath (Join-Path $appDir 'storage-speed.json') -AllowFailure | Out-Null
            }
            catch {
                Write-Status -Message ("Storage speed test failed for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
            }
        }

        if ($captureWifiThroughput) {
            try {
                Invoke-RemoteJsonScript -Serial $targetDevice.AdbSerial -RemoteCommand 'sh /data/local/tmp/wifi-throughput-test.sh' -LocalOutputPath (Join-Path $appDir 'wifi-throughput.json') -AllowFailure | Out-Null
            }
            catch {
                Write-Status -Message ("WiFi throughput test failed for '{0}': {1}" -f $appName, $_.Exception.Message) -ErrorsLog $errorsLog -IsError
            }
        }
    }
}

Write-Status -Message 'Generating markdown report...'
& $reportScriptPath -OutDir $resolvedOutDir
Write-Status -Message ("Benchmark suite complete. Results: {0}" -f $resolvedOutDir)
