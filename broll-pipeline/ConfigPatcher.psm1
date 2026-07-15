Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# NOTE: do NOT pass -Force here. Broll.Common is normally already imported by the caller
# (Invoke-BrollCapture.ps1) into the top-level session. A forced re-import from inside a
# nested module creates a second module instance scoped to this module's own session
# state, which silently un-binds Broll.Common's exported functions (e.g.
# Ensure-BrollCommand) from the caller's scope -- causing "term not recognized" errors
# even though the module "successfully" imported moments earlier.
Import-Module (Join-Path $PSScriptRoot 'Broll.Common.psm1') -ErrorAction SilentlyContinue

function ConvertTo-KeyValueMap {
    param([Parameter(Mandatory = $true)]$InputObject)
    $raw = ConvertTo-BrollHashtable -InputObject $InputObject
    $result = @{}
    foreach ($key in $raw.Keys) {
        $value = $raw[$key]
        if ($null -eq $value) {
            continue
        }
        if ($value -is [bool]) {
            $result[$key] = $value.ToString().ToLowerInvariant()
        }
        else {
            $result[$key] = [string]$value
        }
    }
    return $result
}

function Set-QuotedConfigKeys {
    param(
        # AllowEmptyString: config files that don't exist yet on-device (e.g. a fresh
        # RetroArch install with no retroarch-core-options.cfg) are represented as ''
        # by the caller -- PowerShell mandatory string params reject '' by default.
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][hashtable]$Overrides
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Content -split "`r?`n")) {
        [void]$lines.Add($line)
    }

    foreach ($key in $Overrides.Keys) {
        $escaped = [regex]::Escape($key)
        $replacement = '{0} = "{1}"' -f $key, ($Overrides[$key] -replace '"', '\"')
        $foundIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*$escaped\s*=") {
                $foundIndex = $i
                break
            }
        }
        if ($foundIndex -ge 0) {
            $lines[$foundIndex] = $replacement
        }
        else {
            [void]$lines.Add($replacement)
        }
    }

    return ($lines -join "`n")
}

function Backup-RemoteConfigFile {
    # Idempotent per WorkDir: the FIRST call for a given RemotePath in a job captures the
    # on-device original (or records that the file did not exist). Subsequent calls in the
    # same job are no-ops, so the "original" always reflects pre-job state no matter how many
    # permutations subsequently patch the file.
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    Ensure-BrollDirectory -Path $WorkDir
    $safe = ConvertTo-BrollSafeName -Value $RemotePath
    $backupPath = Join-Path $WorkDir ("backup_{0}.orig" -f $safe)
    $missingMarker = "$backupPath.missing"
    if ((Test-Path -LiteralPath $backupPath) -or (Test-Path -LiteralPath $missingMarker)) {
        return
    }

    $exists = Invoke-BrollAdb -Serial $Serial -Arguments @('shell', "test -f '$RemotePath' && echo EXISTS || echo MISSING") -StepDescription "Checking whether $RemotePath exists" -AllowFailure
    if ($exists.Output -notmatch 'EXISTS') {
        [System.IO.File]::WriteAllText($missingMarker, 'missing')
        Write-BrollStatus -Message "$RemotePath does not exist on device; will remove it on restore."
        return
    }

    Invoke-BrollAdb -Serial $Serial -Arguments @('pull', $RemotePath, $backupPath) -StepDescription "Backing up original $RemotePath" | Out-Null
}

function Restore-RemoteConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    $safe = ConvertTo-BrollSafeName -Value $RemotePath
    $backupPath = Join-Path $WorkDir ("backup_{0}.orig" -f $safe)
    $missingMarker = "$backupPath.missing"

    if (Test-Path -LiteralPath $missingMarker) {
        Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'rm', '-f', $RemotePath) -StepDescription "Removing $RemotePath (did not exist before this job)" -AllowFailure | Out-Null
        return
    }

    if (-not (Test-Path -LiteralPath $backupPath)) {
        Write-BrollStatus -Message "No backup on file for $RemotePath; nothing to restore (was it ever patched?)." -IsWarning
        return
    }

    Invoke-BrollAdb -Serial $Serial -Arguments @('push', $backupPath, $RemotePath) -StepDescription "Restoring original $RemotePath" | Out-Null
}

function Update-RemoteQuotedConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][hashtable]$Overrides,
        [Parameter(Mandatory = $true)][string]$WorkDir,
        [switch]$DryRun
    )

    if ($Overrides.Count -eq 0) {
        return
    }

    if ($DryRun) {
        Write-BrollStatus -Message "DRY RUN: Would patch $RemotePath with keys: $($Overrides.Keys -join ', ')"
        return
    }

    Backup-RemoteConfigFile -Serial $Serial -RemotePath $RemotePath -WorkDir $WorkDir

    $pull = Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'cat', $RemotePath) -StepDescription "Reading $RemotePath" -AllowFailure
    $existingContent = if ($pull.ExitCode -eq 0) { $pull.Output } else { '' }
    $updated = Set-QuotedConfigKeys -Content $existingContent -Overrides $Overrides
    Ensure-BrollDirectory -Path $WorkDir
    $safe = ConvertTo-BrollSafeName -Value $RemotePath
    $local = Join-Path $WorkDir ("patch_{0}.cfg" -f $safe)
    [System.IO.File]::WriteAllText($local, $updated, [System.Text.UTF8Encoding]::new($false))
    $remoteDir = ($RemotePath -replace '/[^/]+$', '')
    if ($remoteDir -and $remoteDir -ne $RemotePath) {
        Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'mkdir', '-p', $remoteDir) -StepDescription "Ensuring $remoteDir exists on device" -AllowFailure | Out-Null
    }
    Invoke-BrollAdb -Serial $Serial -Arguments @('push', $local, $RemotePath) -StepDescription "Pushing patched config to $RemotePath" | Out-Null
}

function Invoke-RetroArchSettingsPatch {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )

    $serial = [string]$Context.Serial
    $workDir = [string]$Context.WorkDir
    $permutation = ConvertTo-BrollHashtable -InputObject $Context.Permutation
    $target = ConvertTo-BrollHashtable -InputObject $Context.Target
    $overrides = @{}
    if ($permutation.ContainsKey('overrides') -and $permutation.overrides) {
        $overrides = ConvertTo-BrollHashtable -InputObject $permutation.overrides
    }

    $retroarchCfgPath = '/storage/emulated/0/RetroArch/retroarch.cfg'
    $coreOptionsPath = '/storage/emulated/0/RetroArch/config/retroarch-core-options.cfg'
    if ($target.ContainsKey('paths') -and $target.paths) {
        $paths = ConvertTo-BrollHashtable -InputObject $target.paths
        if ($paths.ContainsKey('retroarchCfg')) {
            $retroarchCfgPath = [string]$paths.retroarchCfg
        }
        if ($paths.ContainsKey('coreOptionsCfg')) {
            $coreOptionsPath = [string]$paths.coreOptionsCfg
        }
    }

    $retroarchCfgOverrides = @{}
    $coreOptionOverrides = @{}
    if ($overrides.ContainsKey('retroarchCfg') -and $overrides.retroarchCfg) {
        $retroarchCfgOverrides = ConvertTo-KeyValueMap -InputObject $overrides.retroarchCfg
    }
    if ($overrides.ContainsKey('coreOptions') -and $overrides.coreOptions) {
        $coreOptionOverrides = ConvertTo-KeyValueMap -InputObject $overrides.coreOptions
    }

    if ($retroarchCfgOverrides.Count -eq 0 -and $coreOptionOverrides.Count -eq 0) {
        Write-BrollStatus -Message 'No RetroArch overrides supplied for this permutation.'
        return
    }

    Update-RemoteQuotedConfigFile -Serial $serial -RemotePath $retroarchCfgPath -Overrides $retroarchCfgOverrides -WorkDir $workDir -DryRun:$DryRun
    Update-RemoteQuotedConfigFile -Serial $serial -RemotePath $coreOptionsPath -Overrides $coreOptionOverrides -WorkDir $workDir -DryRun:$DryRun
}

function Invoke-RetroArchSettingsRestore {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-BrollStatus -Message 'DRY RUN: Would restore original RetroArch config files.'
        return
    }

    $serial = [string]$Context.Serial
    $workDir = [string]$Context.WorkDir
    $target = ConvertTo-BrollHashtable -InputObject $Context.Target

    $retroarchCfgPath = '/storage/emulated/0/RetroArch/retroarch.cfg'
    $coreOptionsPath = '/storage/emulated/0/RetroArch/config/retroarch-core-options.cfg'
    if ($target.ContainsKey('paths') -and $target.paths) {
        $paths = ConvertTo-BrollHashtable -InputObject $target.paths
        if ($paths.ContainsKey('retroarchCfg')) {
            $retroarchCfgPath = [string]$paths.retroarchCfg
        }
        if ($paths.ContainsKey('coreOptionsCfg')) {
            $coreOptionsPath = [string]$paths.coreOptionsCfg
        }
    }

    Restore-RemoteConfigFile -Serial $serial -RemotePath $retroarchCfgPath -WorkDir $workDir
    Restore-RemoteConfigFile -Serial $serial -RemotePath $coreOptionsPath -WorkDir $workDir
}

function Invoke-RetroArchScenePrep {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )

    $target = ConvertTo-BrollHashtable -InputObject $Context.Target
    if (-not ($target.ContainsKey('scene') -and $target.scene)) {
        return
    }

    $scene = ConvertTo-BrollHashtable -InputObject $target.scene
    $sceneType = if ($scene.ContainsKey('type')) { [string]$scene.type } else { '' }
    if ($sceneType -ne 'retroarch_nci_state_slot') {
        return
    }

    if (-not $scene.ContainsKey('slot')) {
        throw 'RetroArch NCI scene requires scene.slot.'
    }

    $slot = [int]$scene.slot
    # NOTE: observed live hang on real hardware -- when nothing is listening on the NCI UDP
    # port (e.g. RetroArch not fully launched yet / no content loaded), toybox's `nc -u`
    # can outlive the `sh -c` pipeline it's part of once `timeout` kills the shell, and the
    # orphaned nc keeps the adb shell's stdout pipe open, so `adb shell` never sees EOF and
    # hangs indefinitely. Fix: wrap `nc` itself (not the whole pipeline) with `timeout`,
    # redirect nc's stdout/stderr to /dev/null so an orphan can't hold the pipe open, and use
    # -q0 (quit immediately on stdin EOF) to minimize the window for orphaning at all. A
    # client-side -TimeoutSec backstop below guarantees this call can never hang the pipeline
    # even if all of that somehow still fails on some other device/toybox build.
    $command = "echo -n 'LOAD_STATE_SLOT $slot' | timeout 3 nc -u -w1 -q0 127.0.0.1 55355 >/dev/null 2>&1"
    Invoke-BrollAdb -Serial ([string]$Context.Serial) -Arguments @('shell', $command) -StepDescription "RetroArch NCI LOAD_STATE_SLOT $slot" -DryRun:$DryRun -AllowFailure -TimeoutSec 8 | Out-Null
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
    }
}

function Invoke-StubSettingsPatch {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )

    $todo = @(
        "TODO [$Emulator]: discover real settings file path(s) on-device.",
        "TODO [$Emulator]: map benchmark matrix override keys to concrete config keys.",
        "TODO [$Emulator]: implement safe patch/restore semantics similar to RetroArch strategy."
    ) -join ' '
    Write-BrollStatus -Message $todo -IsWarning

    if (-not $DryRun) {
        Write-BrollStatus -Message "No-op patch for '$Emulator' (strategy stub)." -IsWarning
    }
}

function Invoke-StubScenePrep {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )

    $todo = @(
        "TODO [$Emulator]: implement emulator-specific reproducible scene loading.",
        "Expected pattern: pre-stage a known-good save-state file before launch, then load it via app automation."
    ) -join ' '
    Write-BrollStatus -Message $todo -IsWarning
}

function Invoke-StubSettingsRestore {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )
    # Stub strategies never patch anything (see Invoke-StubSettingsPatch), so there is
    # nothing to restore. No-op kept explicit/named so this is easy to find when the stub
    # strategies gain real patch implementations.
}

$script:Strategies = @{
    retroarch   = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-RetroArchSettingsPatch -Context $Context -DryRun:$DryRun }
        RestoreSettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-RetroArchSettingsRestore -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-RetroArchScenePrep -Context $Context -DryRun:$DryRun }
    }
    duckstation = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'duckstation' -Context $Context -DryRun:$DryRun }
        RestoreSettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsRestore -Emulator 'duckstation' -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubScenePrep -Emulator 'duckstation' -Context $Context -DryRun:$DryRun }
    }
    flycast     = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'flycast' -Context $Context -DryRun:$DryRun }
        RestoreSettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsRestore -Emulator 'flycast' -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubScenePrep -Emulator 'flycast' -Context $Context -DryRun:$DryRun }
    }
    aethersx2   = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'aethersx2' -Context $Context -DryRun:$DryRun }
        RestoreSettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsRestore -Emulator 'aethersx2' -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubScenePrep -Emulator 'aethersx2' -Context $Context -DryRun:$DryRun }
    }
}

function Get-ConfigPatcherStrategy {
    param([Parameter(Mandatory = $true)][string]$Emulator)
    $key = $Emulator.ToLowerInvariant()
    if (-not $script:Strategies.ContainsKey($key)) {
        throw "Unsupported emulator '$Emulator'. Supported: $($script:Strategies.Keys -join ', ')"
    }
    return $script:Strategies[$key]
}

function Invoke-ApplyEmulatorOverrides {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )
    $strategy = Get-ConfigPatcherStrategy -Emulator $Emulator
    & $strategy.ApplySettings $Context ([bool]$DryRun)
}

function Invoke-PrepareEmulatorScene {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )
    $strategy = Get-ConfigPatcherStrategy -Emulator $Emulator
    & $strategy.PrepareScene $Context ([bool]$DryRun)
}

function Invoke-RestoreEmulatorConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Emulator,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [switch]$DryRun
    )
    $strategy = Get-ConfigPatcherStrategy -Emulator $Emulator
    & $strategy.RestoreSettings $Context ([bool]$DryRun)
}

Export-ModuleMember -Function @(
    'Get-ConfigPatcherStrategy',
    'Invoke-ApplyEmulatorOverrides',
    'Invoke-PrepareEmulatorScene',
    'Invoke-RestoreEmulatorConfig'
)
