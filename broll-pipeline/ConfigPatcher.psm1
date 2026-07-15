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
        [Parameter(Mandatory = $true)][string]$Content,
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

    $pull = Invoke-BrollAdb -Serial $Serial -Arguments @('shell', 'cat', $RemotePath) -StepDescription "Reading $RemotePath"
    $updated = Set-QuotedConfigKeys -Content $pull.Output -Overrides $Overrides
    Ensure-BrollDirectory -Path $WorkDir
    $safe = ConvertTo-BrollSafeName -Value $RemotePath
    $local = Join-Path $WorkDir ("patch_{0}.cfg" -f $safe)
    [System.IO.File]::WriteAllText($local, $updated, [System.Text.UTF8Encoding]::new($false))
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
    $command = "timeout 3 sh -c 'echo -n ""LOAD_STATE_SLOT $slot"" | nc -u -w1 -q1 127.0.0.1 55355'"
    Invoke-BrollAdb -Serial ([string]$Context.Serial) -Arguments @('shell', $command) -StepDescription "RetroArch NCI LOAD_STATE_SLOT $slot" -DryRun:$DryRun | Out-Null
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

$script:Strategies = @{
    retroarch   = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-RetroArchSettingsPatch -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-RetroArchScenePrep -Context $Context -DryRun:$DryRun }
    }
    duckstation = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'duckstation' -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubScenePrep -Emulator 'duckstation' -Context $Context -DryRun:$DryRun }
    }
    flycast     = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'flycast' -Context $Context -DryRun:$DryRun }
        PrepareScene  = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubScenePrep -Emulator 'flycast' -Context $Context -DryRun:$DryRun }
    }
    aethersx2   = @{
        ApplySettings = { param([hashtable]$Context, [bool]$DryRun) Invoke-StubSettingsPatch -Emulator 'aethersx2' -Context $Context -DryRun:$DryRun }
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

Export-ModuleMember -Function @(
    'Get-ConfigPatcherStrategy',
    'Invoke-ApplyEmulatorOverrides',
    'Invoke-PrepareEmulatorScene'
)
