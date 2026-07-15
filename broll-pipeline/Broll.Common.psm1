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
    # Enforces a hard wall-clock ceiling on every external process this pipeline spawns.
    # Rationale: a hung adb/nc/scrcpy call (observed live: toybox nc orphaning under adb
    # shell, holding a pipe open so adb shell never returns EOF) must never be allowed to
    # block indefinitely -- doing so would starve the calling script's try/finally
    # device-restore safety net of a chance to ever run. On timeout, the process (and any
    # children it spawned) is force-killed and the call is treated as a failure (or
    # ignored if -AllowFailure), same as a nonzero exit code.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StepDescription = $FilePath,
        [switch]$AllowFailure,
        [switch]$DryRun,
        [int]$TimeoutSec = 30
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

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($arg in $Arguments) { $psi.ArgumentList.Add($arg) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $stdout = [System.Text.StringBuilder]::new()
    $stderr = [System.Text.StringBuilder]::new()
    $outEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action { if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data).Append([Environment]::NewLine) | Out-Null } } -MessageData $stdout
    $errEvent = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action { if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data).Append([Environment]::NewLine) | Out-Null } } -MessageData $stderr

    try {
        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()

        $timedOut = -not $proc.WaitForExit($TimeoutSec * 1000)
        if ($timedOut) {
            Write-BrollStatus -Message "$StepDescription exceeded ${TimeoutSec}s timeout; force-killing process tree." -IsWarning
            try { $proc.Kill($true) } catch { }
            $proc.WaitForExit(5000) | Out-Null
        }
        else {
            # Give async output handlers a brief moment to flush the final lines.
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
    $text = ($stdout.ToString() + $stderr.ToString()).TrimEnd([Environment]::NewLine.ToCharArray())

    if ($timedOut -and -not $AllowFailure) {
        throw ("{0} timed out after {1}s and was force-killed.`n{2}" -f $StepDescription, $TimeoutSec, $text)
    }
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
        [switch]$DryRun,
        [int]$TimeoutSec = 30
    )

    $allArgs = @('-s', $Serial) + $Arguments
    return Invoke-BrollExternal -FilePath 'adb' -Arguments $allArgs -StepDescription $StepDescription -AllowFailure:$AllowFailure -DryRun:$DryRun -TimeoutSec $TimeoutSec
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
