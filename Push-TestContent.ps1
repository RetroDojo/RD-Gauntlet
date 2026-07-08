[CmdletBinding()]
param(
    [string]$DeviceName,
    [string]$AdbSerial,
    [string]$DevicesConfig = ".\devices.json",
    [string]$ContentConfig = ".\test-content.json",
    [string[]]$Systems,
    [string]$BiosRoot = "D:\bios",
    [int]$ReserveFreeMb = 512,
    [switch]$DryRun
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

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$IsWarning
    )

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    if ($IsWarning) {
        Write-Warning $line
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
        throw ("{0} failed (exit {1})`n{2}" -f $StepDescription, $exitCode, $text)
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

function Resolve-TargetSerial {
    param(
        [string]$RequestedName,
        [string]$RequestedSerial,
        [string]$DevicesConfigPath
    )

    $connectedSerials = @(Get-ConnectedDeviceSerials)
    if ([string]::IsNullOrWhiteSpace($RequestedSerial) -eq $false) {
        if ($connectedSerials -notcontains $RequestedSerial) {
            throw "Requested serial '$RequestedSerial' is not connected."
        }
        return $RequestedSerial
    }

    $devices = @()
    if (Test-Path -LiteralPath $DevicesConfigPath) {
        $loaded = Get-Content -LiteralPath $DevicesConfigPath -Raw | ConvertFrom-Json
        if ($loaded) {
            $devices = @($loaded | ForEach-Object { $_ })
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedName)) {
        $selected = $devices | Where-Object { $_.name -eq $RequestedName } | Select-Object -First 1
        if (-not $selected) {
            throw "Device '$RequestedName' not found in $DevicesConfigPath."
        }

        $serial = [string]$selected.adbSerial
        if ([string]::IsNullOrWhiteSpace($serial)) {
            throw "Device '$RequestedName' has no adbSerial. Pass -AdbSerial explicitly."
        }

        if ($connectedSerials -notcontains $serial) {
            throw "Configured serial '$serial' for '$RequestedName' is not connected."
        }

        return $serial
    }

    if ($connectedSerials.Count -eq 1) {
        return $connectedSerials[0]
    }

    if ($connectedSerials.Count -eq 0) {
        throw 'No adb devices connected.'
    }

    throw "Multiple adb devices connected ($($connectedSerials -join ', ')). Pass -AdbSerial or -DeviceName."
}

function Get-AvailableBytes {
    param([Parameter(Mandatory = $true)][string]$Serial)

    $df = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'df', '/storage/emulated/0') -StepDescription 'Checking device free space'
    $lines = $df.Output -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
    if ($lines.Count -lt 2) {
        return $null
    }

    $parts = $lines[1] -split '\s+'
    if ($parts.Count -lt 4) {
        return $null
    }

    $availableKb = 0L
    if (-not [long]::TryParse($parts[3], [ref]$availableKb)) {
        return $null
    }

    return ($availableKb * 1KB)
}

function Get-RemoteDirectoryFromPath {
    param([Parameter(Mandatory = $true)][string]$RemotePath)

    $lastSlash = $RemotePath.LastIndexOf('/')
    if ($lastSlash -le 0) {
        return '/storage/emulated/0'
    }

    return $RemotePath.Substring(0, $lastSlash)
}

function Get-BiosFilesForSystem {
    param(
        [Parameter(Mandatory = $true)][string]$SystemName,
        [Parameter(Mandatory = $true)][string]$FlatBiosRoot
    )

    if (-not (Test-Path -LiteralPath $FlatBiosRoot)) {
        return @()
    }

    $allFiles = @(Get-ChildItem -LiteralPath $FlatBiosRoot -File -ErrorAction SilentlyContinue)
    if ($allFiles.Count -eq 0) {
        return @()
    }

    switch ($SystemName.ToLowerInvariant()) {
        'ps1' {
            return @($allFiles | Where-Object { $_.Name -match '(?i)^scph\d+\.bin$' })
        }
        'ps2' {
            return @($allFiles | Where-Object { $_.Name -match '(?i)^ps2-.*\.bin$|^SCPH-\d+\.bin$' })
        }
        'dreamcast' {
            return @($allFiles | Where-Object { $_.Name -match '(?i)^dc_(boot|flash|nvmem)\.bin$' })
        }
        'gc' {
            return @($allFiles | Where-Object { $_.Name -match '(?i)^IPL\.bin$' })
        }
        default {
            return @()
        }
    }
}

$devicesConfigPath = Resolve-SuitePath -Path $DevicesConfig
$contentConfigPath = Resolve-SuitePath -Path $ContentConfig
if (-not (Test-Path -LiteralPath $contentConfigPath)) {
    throw "Content config not found: $contentConfigPath"
}

$serial = Resolve-TargetSerial -RequestedName $DeviceName -RequestedSerial $AdbSerial -DevicesConfigPath $devicesConfigPath
Write-Status -Message "Using device serial: $serial"

$contentLoaded = Get-Content -LiteralPath $contentConfigPath -Raw | ConvertFrom-Json
$entries = @($contentLoaded | ForEach-Object { $_ })
if ($entries.Count -eq 0) {
    throw "No entries in $contentConfigPath"
}

if ($Systems -and $Systems.Count -gt 0) {
    $set = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($sys in $Systems) {
        [void]$set.Add([string]$sys)
    }
    $entries = @($entries | Where-Object { $set.Contains([string]$_.system) })
    if ($entries.Count -eq 0) {
        throw 'No content entries matched -Systems filter.'
    }
}

$defaultTargetBySystem = @{
    'nes' = '/storage/emulated/0/ROMs/nes'
    'snes' = '/storage/emulated/0/ROMs/snes'
    'md' = '/storage/emulated/0/ROMs/megadrive'
    'gba' = '/storage/emulated/0/ROMs/gba'
    'arcade' = '/storage/emulated/0/ROMs/mame'
    'nds' = '/storage/emulated/0/ROMs/nds'
    'n64' = '/storage/emulated/0/ROMs/n64'
    'psp' = '/storage/emulated/0/ROMs/psp'
    'dreamcast' = '/storage/emulated/0/ROMs/dreamcast'
}

$results = New-Object System.Collections.Generic.List[object]
$reserveBytes = [long]$ReserveFreeMb * 1MB
$availableBytes = Get-AvailableBytes -Serial $serial
if ($null -ne $availableBytes) {
    Write-Status -Message ("Free space before push: {0:N2} GB" -f ($availableBytes / 1GB))
}

foreach ($entry in $entries) {
    $name = [string]$entry.name
    $system = [string]$entry.system
    $localPath = [string]$entry.romPath
    if ([string]::IsNullOrWhiteSpace($localPath) -or -not (Test-Path -LiteralPath $localPath)) {
        Write-Status -Message "ROM missing for '$name': $localPath" -IsWarning
        $results.Add([pscustomobject]@{ name = $name; system = $system; status = 'missing_local'; localPath = $localPath })
        continue
    }

    $remotePath = if ($entry.PSObject.Properties['devicePath'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.devicePath)) {
        [string]$entry.devicePath
    }
    elseif ($defaultTargetBySystem.ContainsKey($system)) {
        $fileName = [System.IO.Path]::GetFileName($localPath)
        "$($defaultTargetBySystem[$system])/$fileName"
    }
    else {
        $fileName = [System.IO.Path]::GetFileName($localPath)
        "/storage/emulated/0/ROMs/$system/$fileName"
    }

    $remoteDir = Get-RemoteDirectoryFromPath -RemotePath $remotePath
    $fileInfo = Get-Item -LiteralPath $localPath

    if ($null -ne $availableBytes -and ($fileInfo.Length + $reserveBytes) -gt $availableBytes) {
        Write-Status -Message ("Skipping '{0}' ({1:N2} MB): insufficient free space on device." -f $name, ($fileInfo.Length / 1MB)) -IsWarning
        $results.Add([pscustomobject]@{ name = $name; system = $system; status = 'skipped_low_space'; localPath = $localPath; remotePath = $remotePath })
        continue
    }

    Write-Status -Message ("Push {0} -> {1}" -f $localPath, $remotePath)
    if (-not $DryRun.IsPresent) {
        Invoke-Adb -Arguments @('-s', $serial, 'shell', 'mkdir', '-p', $remoteDir) -StepDescription "Creating $remoteDir" | Out-Null
        Invoke-Adb -Arguments @('-s', $serial, 'push', $localPath, $remotePath) -StepDescription "Pushing $name" | Out-Null
        if ($null -ne $availableBytes) {
            $availableBytes -= [long]$fileInfo.Length
        }
    }

    $results.Add([pscustomobject]@{ name = $name; system = $system; status = if ($DryRun) { 'dry_run' } else { 'pushed' }; localPath = $localPath; remotePath = $remotePath })
}

$biosSystems = @('ps1', 'ps2', 'gc', 'dreamcast')
$biosTargetDirs = @{
    'ps1' = @('/storage/emulated/0/ROMs/bios/ps1', '/storage/emulated/0/RetroArch/system')
    'ps2' = @('/storage/emulated/0/ROMs/bios/ps2')
    'gc' = @('/storage/emulated/0/ROMs/bios/gc')
    'dreamcast' = @('/storage/emulated/0/ROMs/bios/dreamcast', '/storage/emulated/0/RetroArch/system')
}

foreach ($biosSystem in $biosSystems) {
    $biosFiles = @(Get-BiosFilesForSystem -SystemName $biosSystem -FlatBiosRoot $BiosRoot)
    if ($biosFiles.Count -eq 0) {
        Write-Status -Message "BIOS not found for '$biosSystem' in flat source '$BiosRoot', skipping." -IsWarning
        continue
    }

    $remoteBiosDirs = if ($biosTargetDirs.ContainsKey($biosSystem)) { @($biosTargetDirs[$biosSystem]) } else { @("/storage/emulated/0/ROMs/bios/$biosSystem") }
    Write-Status -Message "Found BIOS files for '$biosSystem' in ${BiosRoot}: $($biosFiles.Count)."
    if (-not $DryRun.IsPresent) {
        foreach ($remoteBiosDir in $remoteBiosDirs) {
            Invoke-Adb -Arguments @('-s', $serial, 'shell', 'mkdir', '-p', $remoteBiosDir) -StepDescription "Creating BIOS dir $remoteBiosDir" | Out-Null
        }
    }

    foreach ($biosFile in $biosFiles) {
        if ($null -ne $availableBytes -and ($biosFile.Length + $reserveBytes) -gt $availableBytes) {
            Write-Status -Message ("Skipping BIOS file '{0}' for {1}: insufficient free space." -f $biosFile.Name, $biosSystem) -IsWarning
            continue
        }

        foreach ($remoteBiosDir in $remoteBiosDirs) {
            $remoteBiosPath = "$remoteBiosDir/$($biosFile.Name)"
            Write-Status -Message ("Push BIOS {0} -> {1}" -f $biosFile.FullName, $remoteBiosPath)
            if (-not $DryRun.IsPresent) {
                Invoke-Adb -Arguments @('-s', $serial, 'push', $biosFile.FullName, $remoteBiosPath) -StepDescription "Pushing BIOS $($biosFile.Name)" | Out-Null
                if ($null -ne $availableBytes) {
                    $availableBytes -= [long]$biosFile.Length
                }
            }
        }
    }
}

$reportPath = Join-Path $PSScriptRoot 'last-push-report.json'
[System.IO.File]::WriteAllText($reportPath, (ConvertTo-Json -InputObject $results -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Status -Message "Push complete. Report: $reportPath"