Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-BrollPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Write-BrollStatus {
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

function Ensure-BrollDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-BrollCommand {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-BrollExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StepDescription = $FilePath,
        [switch]$AllowFailure,
        [switch]$DryRun
    )

    $joined = ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
    }) -join ' '
    Write-BrollStatus -Message ("{0}: {1} {2}" -f $StepDescription, $FilePath, $joined)
    if ($DryRun) {
        return [pscustomobject]@{
            ExitCode = 0
            Output   = '[dry-run]'
        }
    }

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw ("{0} failed with exit code {1}`n{2}" -f $StepDescription, $exitCode, $text)
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $text
    }
}

function Invoke-BrollAdb {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StepDescription = 'adb command',
        [switch]$AllowFailure,
        [switch]$DryRun
    )

    $allArgs = @('-s', $Serial) + $Arguments
    return Invoke-BrollExternal -FilePath 'adb' -Arguments $allArgs -StepDescription $StepDescription -AllowFailure:$AllowFailure -DryRun:$DryRun
}

function Get-BrollConnectedSerials {
    $result = Invoke-BrollExternal -FilePath 'adb' -Arguments @('devices') -StepDescription 'Enumerating adb devices'
    $serials = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ($line -match '^(?<serial>\S+)\s+device$') {
            $serials += $Matches.serial
        }
    }
    return $serials
}

function Resolve-BrollSerial {
    param(
        [string]$ExplicitSerial,
        [string]$MatrixSerial
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitSerial)) {
        return $ExplicitSerial
    }
    if (-not [string]::IsNullOrWhiteSpace($MatrixSerial)) {
        return $MatrixSerial
    }

    $connected = @(Get-BrollConnectedSerials)
    if ($connected.Count -eq 1) {
        return $connected[0]
    }
    if ($connected.Count -eq 0) {
        throw 'No adb devices connected. Pass -DeviceSerial or set device.serial in matrix.'
    }
    throw "Multiple adb devices connected ($($connected -join ', ')). Pass -DeviceSerial or set device.serial in matrix."
}

function ConvertTo-BrollSafeName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = $Value -replace '[^A-Za-z0-9._-]+', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'item'
    }
    return $safe
}

function ConvertTo-BrollHashtable {
    param([Parameter(Mandatory = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        return $InputObject
    }

    $table = @{}
    if ($InputObject -is [pscustomobject]) {
        foreach ($property in $InputObject.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }
        return $table
    }

    throw "Expected hashtable/pscustomobject. Got: $($InputObject.GetType().FullName)"
}

function Write-BrollJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object,
        [int]$Depth = 12
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        Ensure-BrollDirectory -Path $directory
    }
    $json = ConvertTo-Json -InputObject $Object -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

Export-ModuleMember -Function @(
    'Resolve-BrollPath',
    'Write-BrollStatus',
    'Ensure-BrollDirectory',
    'Ensure-BrollCommand',
    'Invoke-BrollExternal',
    'Invoke-BrollAdb',
    'Get-BrollConnectedSerials',
    'Resolve-BrollSerial',
    'ConvertTo-BrollSafeName',
    'ConvertTo-BrollHashtable',
    'Write-BrollJson'
)
