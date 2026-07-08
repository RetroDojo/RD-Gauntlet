[CmdletBinding(DefaultParameterSetName = 'RunApp')]
param(
    [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
    [string]$ImagePath,

    [Parameter(ParameterSetName = 'Compare', Mandatory = $true)]
    [string]$ImageA,
    [Parameter(ParameterSetName = 'Compare', Mandatory = $true)]
    [string]$ImageB,

    [Parameter(ParameterSetName = 'RunApp', Mandatory = $true)]
    [string]$RunDir,
    [Parameter(ParameterSetName = 'RunApp', Mandatory = $true)]
    [string]$AppName,

    [Parameter(ParameterSetName = 'CrossRun', Mandatory = $true)]
    [string]$RunDirA,
    [Parameter(ParameterSetName = 'CrossRun', Mandatory = $true)]
    [string]$RunDirB,
    [Parameter(ParameterSetName = 'CrossRun', Mandatory = $true)]
    [string]$CrossAppName,
    [Parameter(ParameterSetName = 'CrossRun')]
    [string]$ShotName = '00-launch.png',

    [string]$OutDir
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

function Get-SafeName {
    param([Parameter(Mandatory = $true)][string]$Value)
    $safe = $Value -replace '[^A-Za-z0-9._-]+', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'item'
    }
    return $safe
}

function Resolve-AppDir {
    param(
        [Parameter(Mandatory = $true)][string]$BaseRunDir,
        [Parameter(Mandatory = $true)][string]$AppName
    )

    $direct = Join-Path $BaseRunDir $AppName
    if (Test-Path -LiteralPath $direct) {
        return $direct
    }

    $safe = Join-Path $BaseRunDir (Get-SafeName -Value $AppName)
    if (Test-Path -LiteralPath $safe) {
        return $safe
    }

    throw "App folder not found under '$BaseRunDir' for name '$AppName'."
}

function Invoke-PythonChecked {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    & python @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: python $($Args -join ' ')"
    }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutDir = Join-Path $PSScriptRoot ("results\visual-analysis\$stamp")
}
$resolvedOutDir = Resolve-SuitePath -Path $OutDir
New-Item -ItemType Directory -Path $resolvedOutDir -Force | Out-Null

$analyzeScript = Resolve-SuitePath -Path '.\Analyze-Screenshot.py'
$compareScript = Resolve-SuitePath -Path '.\Compare-Screenshots.py'

if (-not (Test-Path -LiteralPath $analyzeScript)) {
    throw "Analyze-Screenshot.py not found at $analyzeScript"
}
if (-not (Test-Path -LiteralPath $compareScript)) {
    throw "Compare-Screenshots.py not found at $compareScript"
}

switch ($PSCmdlet.ParameterSetName) {
    'Single' {
        $resolved = Resolve-SuitePath -Path $ImagePath
        $outJson = Join-Path $resolvedOutDir ("{0}.analysis.json" -f (Get-SafeName -Value ([System.IO.Path]::GetFileNameWithoutExtension($resolved))))
        Invoke-PythonChecked -Args @($analyzeScript, $resolved, '--out-json', $outJson)
        Write-Host "Wrote $outJson"
    }
    'Compare' {
        $resolvedA = Resolve-SuitePath -Path $ImageA
        $resolvedB = Resolve-SuitePath -Path $ImageB
        $outJson = Join-Path $resolvedOutDir 'comparison.json'
        $outMd = Join-Path $resolvedOutDir 'comparison.md'
        Invoke-PythonChecked -Args @($compareScript, $resolvedA, $resolvedB, '--out-json', $outJson, '--out-md', $outMd)
        Write-Host "Wrote $outJson"
        Write-Host "Wrote $outMd"
    }
    'RunApp' {
        $resolvedRunDir = Resolve-SuitePath -Path $RunDir
        $appDir = Resolve-AppDir -BaseRunDir $resolvedRunDir -AppName $AppName
        $launch = Join-Path $appDir '00-launch.png'
        $end = Join-Path $appDir '99-end.png'

        if (-not (Test-Path -LiteralPath $launch)) { throw "Missing screenshot: $launch" }
        if (-not (Test-Path -LiteralPath $end)) { throw "Missing screenshot: $end" }

        $prefix = Get-SafeName -Value $AppName
        $launchJson = Join-Path $resolvedOutDir ("{0}.00-launch.analysis.json" -f $prefix)
        $endJson = Join-Path $resolvedOutDir ("{0}.99-end.analysis.json" -f $prefix)
        $pairJson = Join-Path $resolvedOutDir ("{0}.launch-vs-end.comparison.json" -f $prefix)
        $pairMd = Join-Path $resolvedOutDir ("{0}.launch-vs-end.comparison.md" -f $prefix)

        Invoke-PythonChecked -Args @($analyzeScript, $launch, '--out-json', $launchJson)
        Invoke-PythonChecked -Args @($analyzeScript, $end, '--out-json', $endJson)
        Invoke-PythonChecked -Args @(
            $compareScript,
            $launch,
            $end,
            '--label-a', "$AppName 00-launch",
            '--label-b', "$AppName 99-end",
            '--out-json', $pairJson,
            '--out-md', $pairMd
        )

        Write-Host "Wrote $launchJson"
        Write-Host "Wrote $endJson"
        Write-Host "Wrote $pairJson"
        Write-Host "Wrote $pairMd"
    }
    'CrossRun' {
        $resolvedRunA = Resolve-SuitePath -Path $RunDirA
        $resolvedRunB = Resolve-SuitePath -Path $RunDirB
        $appDirA = Resolve-AppDir -BaseRunDir $resolvedRunA -AppName $CrossAppName
        $appDirB = Resolve-AppDir -BaseRunDir $resolvedRunB -AppName $CrossAppName

        $imagePathA = Join-Path $appDirA $ShotName
        $imagePathB = Join-Path $appDirB $ShotName
        if (-not (Test-Path -LiteralPath $imagePathA)) { throw "Missing screenshot: $imagePathA" }
        if (-not (Test-Path -LiteralPath $imagePathB)) { throw "Missing screenshot: $imagePathB" }

        $prefix = Get-SafeName -Value ("{0}_{1}" -f $CrossAppName, [System.IO.Path]::GetFileNameWithoutExtension($ShotName))
        $outJson = Join-Path $resolvedOutDir ("{0}.cross-run.comparison.json" -f $prefix)
        $outMd = Join-Path $resolvedOutDir ("{0}.cross-run.comparison.md" -f $prefix)
        Invoke-PythonChecked -Args @(
            $compareScript,
            $imagePathA,
            $imagePathB,
            '--label-a', "$($resolvedRunA | Split-Path -Leaf) $CrossAppName $ShotName",
            '--label-b', "$($resolvedRunB | Split-Path -Leaf) $CrossAppName $ShotName",
            '--out-json', $outJson,
            '--out-md', $outMd
        )

        Write-Host "Wrote $outJson"
        Write-Host "Wrote $outMd"
    }
}

