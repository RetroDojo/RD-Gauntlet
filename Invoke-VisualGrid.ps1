[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RunDir,

    [string]$OutHtml,

    [string[]]$AppName
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

function Invoke-PythonChecked {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    & python @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: python $($Args -join ' ')"
    }
}

if ([string]::IsNullOrWhiteSpace($OutHtml)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutHtml = Join-Path $PSScriptRoot ("results\visual-grid\visual-grid-$stamp.html")
}

$scriptPath = Resolve-SuitePath -Path '.\Build-VisualGrid.py'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Build-VisualGrid.py not found at $scriptPath"
}

$resolvedRunDirs = @()
foreach ($dir in $RunDir) {
    $resolvedRunDirs += (Resolve-SuitePath -Path $dir)
}

$resolvedOutHtml = Resolve-SuitePath -Path $OutHtml
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutHtml)) | Out-Null

$argsList = @()
$argsList += $scriptPath
$argsList += $resolvedRunDirs
$argsList += '--out-html'
$argsList += $resolvedOutHtml

if ($AppName) {
    foreach ($app in $AppName) {
        $argsList += '--app-filter'
        $argsList += $app
    }
}

Invoke-PythonChecked -Args $argsList
Write-Host "Wrote $resolvedOutHtml"
