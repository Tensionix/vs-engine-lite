<#
.SYNOPSIS
  Installs the canonical VapourSynth plugin stack.

.DESCRIPTION
  The install manifest separates maintained PyPI packages from vsrepo binary
  plugins. The plugin directory is cleaned before installation. Every package
  is verified by its Python module or VapourSynth namespace after installation.
  MLRT is intentionally outside this installer and remains a separate Full-only
  payload.
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [switch]$NoCUDA,
    [string[]]$Plugins = @()
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$VSDir = Join-Path $ProjectRoot 'system_core\vapoursynth'
$VSPython = Join-Path $VSDir 'python.exe'
$ManifestPath = Join-Path $ProjectRoot 'install\vs_plugins.json'

if (-not (Test-Path -LiteralPath $VSPython)) {
    throw "VS-host Python not found at $VSPython. Run Install-Portable-VapourSynth.cmd first."
}
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Plugin manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema_version -ne 1) {
    throw "Unsupported plugin manifest schema: $($manifest.schema_version)"
}

$pluginDirProbe = (& $VSPython -c "import vapoursynth; print(vapoursynth.get_plugin_dir())" 2>$null | Select-Object -Last 1)
if ([string]::IsNullOrWhiteSpace($pluginDirProbe)) {
    throw 'Could not resolve the portable VapourSynth plugin directory.'
}
$VSPluginDir = $pluginDirProbe.Trim()
if (-not (Test-Path -LiteralPath $VSPluginDir)) {
    New-Item -Path $VSPluginDir -ItemType Directory -Force | Out-Null
}

$selected = @{}
foreach ($id in $Plugins) {
    if (-not [string]::IsNullOrWhiteSpace($id)) { $selected[$id.ToLowerInvariant()] = $true }
}
$customSelection = $selected.Count -gt 0

$knownIds = @{}
foreach ($group in @($manifest.python_packages, $manifest.vsrepo_packages, $manifest.optional_cuda_packages)) {
    foreach ($item in $group) { $knownIds[[string]$item.id.ToLowerInvariant()] = $true }
}
foreach ($id in $selected.Keys) {
    if (-not $knownIds.ContainsKey($id)) { throw "Unknown plugin id in -Plugins: $id" }
}

function Test-Selected {
    param([string]$Id, [switch]$Infrastructure)
    if ($Infrastructure) { return $true }
    if (-not $customSelection) { return $true }
    return $selected.ContainsKey($Id.ToLowerInvariant())
}

function Test-Probe {
    param([Parameter(Mandatory=$true)]$Item)

    if ($Item.probe -eq 'module') {
        $code = "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('$($Item.name)') else 1)"
    } elseif ($Item.probe -eq 'namespace') {
        $code = "import vapoursynth as vs,sys; sys.exit(0 if hasattr(vs.core, '$($Item.name)') else 1)"
    } else {
        throw "Unknown probe type '$($Item.probe)' for $($Item.id)"
    }
    & $VSPython -c $code 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-PyPIPackage {
    param([Parameter(Mandatory=$true)]$Item)

    Write-Host "      [PYPI] $($Item.package)"
    $pipArguments = @('-m', 'pip', 'install', '--upgrade', '--quiet', '--no-warn-script-location')
    if ($Item.PSObject.Properties['force_reinstall'] -and [bool]$Item.force_reinstall) {
        $pipArguments += '--force-reinstall'
    }
    if ($Item.PSObject.Properties['no_dependencies'] -and [bool]$Item.no_dependencies) {
        $pipArguments += '--no-deps'
    }
    $pipArguments += [string]$Item.package
    & $VSPython @pipArguments 2>&1 |
        ForEach-Object { Write-Host "        $_" }
    if ($LASTEXITCODE -ne 0) { return $false }
    return (Test-Probe -Item $Item)
}

function Test-VsrepoOutput {
    param([object[]]$Output)
    return -not [bool]($Output | Where-Object {
        $_ -match '(?i)failed to download|failed to decompress|packages? failed'
    })
}

Write-Host '======================================================================'
Write-Host '  AUDION VAPOURSYNTH - CANONICAL PLUGIN INSTALLER'
Write-Host '======================================================================'
Write-Host "VS Python:   $VSPython"
Write-Host "Plugin dir:  $VSPluginDir"
Write-Host "Manifest:    $ManifestPath"
Write-Host "CUDA plugin: $(if ($NoCUDA) { 'disabled' } else { 'enabled' })"
Write-Host ''

# Cleaning must happen before PyPI wheels such as vapoursynth-znedi3 place
# their DLL and weight file in the VapourSynth plugin directory.
Write-Host '[1/6] Cleaning the owned base-plugin area...'
Get-ChildItem -LiteralPath $VSPluginDir -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'vsmlrt' } |
    Remove-Item -Recurse -Force
Write-Host '      [OK] Base plugin area is clean; existing MLRT subtree was preserved.'

Write-Host '[2/6] Removing conflicting legacy/aggregate Python packages...'
foreach ($packageName in @($manifest.remove_python_packages)) {
    & $VSPython -m pip uninstall --yes --quiet $packageName 2>&1 |
        ForEach-Object { Write-Host "        $_" }
}
Write-Host '      [OK] Conflicting package families removed.'

$ok = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

Write-Host '[3/6] Installing maintained PyPI packages...'
foreach ($item in $manifest.python_packages) {
    $infrastructure = $item.id -in @('vsrepo', 'vsutil')
    if (-not (Test-Selected -Id $item.id -Infrastructure:$infrastructure)) { continue }
    if (Install-PyPIPackage -Item $item) {
        $ok.Add([string]$item.id)
        Write-Host "      [OK] $($item.id)"
    } else {
        $failed.Add([string]$item.id)
        Write-Host "      [FAIL] $($item.id)"
    }
}
if ($failed.Count -gt 0) { throw "Required PyPI package installation failed: $($failed -join ', ')" }

$VSRepoPy = (& $VSPython -c "import pathlib,vsrepo; print(pathlib.Path(vsrepo.__file__).with_name('vsrepo.py'))" 2>$null | Select-Object -Last 1)
if ([string]::IsNullOrWhiteSpace($VSRepoPy) -or -not (Test-Path -LiteralPath $VSRepoPy.Trim())) {
    throw 'vsrepo.py was not found in VS-host site-packages.'
}
$VSRepoPy = $VSRepoPy.Trim()

# vsrepo downloads plugin binaries from GitHub anonymously, and 60 requests an
# hour is not enough for this manifest. It is a PyPI package reinstalled by this
# same script, so the token is handed to it from outside instead.
$VSRepoAuth = Join-Path $PSScriptRoot 'vsrepo_github_auth.py'
if (-not (Test-Path -LiteralPath $VSRepoAuth)) {
    throw "vsrepo_github_auth.py is missing beside this script: $VSRepoAuth"
}

Write-Host '[4/6] Refreshing the official vsrepo package database...'
Push-Location $VSDir
try {
    $updated = $false
    for ($attempt = 1; $attempt -le 3 -and -not $updated; $attempt++) {
        & $VSPython $VSRepoAuth $VSRepoPy update
        $updated = $LASTEXITCODE -eq 0
        if (-not $updated -and $attempt -lt 3) {
            Write-Host "      [RETRY $attempt/3] vsrepo database update failed; waiting before retry."
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
    if (-not $updated) { throw 'vsrepo update failed after 3 attempts.' }
} finally {
    Pop-Location
}
Write-Host '      [OK] Package database refreshed.'

$vsrepoItems = @($manifest.vsrepo_packages)
if (-not $NoCUDA) { $vsrepoItems += @($manifest.optional_cuda_packages) }

Write-Host '[5/6] Installing native plugins and VS scripts through vsrepo...'
Push-Location $VSDir
try {
    foreach ($item in $vsrepoItems) {
        if (-not (Test-Selected -Id $item.id)) { continue }
        $arguments = @($VSRepoAuth, $VSRepoPy, 'install', [string]$item.id)
        if ($item.PSObject.Properties['skip_dependencies'] -and [bool]$item.skip_dependencies) {
            $arguments += '-d'
            Write-Host "      [VSREPO] $($item.id) (dependency resolution disabled; dependencies are canonical packages)"
        } else {
            Write-Host "      [VSREPO] $($item.id)"
        }
        $installed = $false
        for ($attempt = 1; $attempt -le 3 -and -not $installed; $attempt++) {
            $output = @(& $VSPython @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $output | ForEach-Object { Write-Host "        $_" }
            $installed = $exitCode -eq 0 -and (Test-VsrepoOutput -Output $output)
            if (-not $installed -and $attempt -lt 3) {
                Write-Host "        [RETRY $attempt/3] $($item.id) failed; waiting before retry."
                Start-Sleep -Seconds (3 * $attempt)
            }
        }
        if ($installed) {
            $ok.Add([string]$item.id)
        } else {
            $failed.Add([string]$item.id)
        }
    }
} finally {
    Pop-Location
}

Write-Host '[6/6] Verifying imports and VapourSynth namespaces...'
$allItems = @($manifest.python_packages) + @($vsrepoItems)
foreach ($item in $allItems) {
    $infrastructure = $item.id -in @('vsrepo', 'vsutil')
    if (-not (Test-Selected -Id $item.id -Infrastructure:$infrastructure)) { continue }
    if (Test-Probe -Item $item) {
        Write-Host "      [OK] $($item.id): $($item.probe) '$($item.name)'"
    } else {
        if (-not $failed.Contains([string]$item.id)) { $failed.Add([string]$item.id) }
        Write-Host "      [FAIL] $($item.id): missing $($item.probe) '$($item.name)'"
    }
}

if ($Plugins.Count -eq 0) {
    Write-Host '      [SMOKE] Rendering synthetic QTGMC and NNEDI3 frames...'
    $smokeCode = @'
import vapoursynth as vs
import havsfunc
import nnedi3_resample

core = vs.core
clip = core.std.BlankClip(width=640, height=480, format=vs.YUV420P8, length=2, fpsnum=25)
qtgmc = havsfunc.QTGMC(clip, Preset="Ultra Fast", TFF=True)
qtgmc.get_frame(0)
resized = nnedi3_resample.nnedi3_resample(clip, target_width=320, target_height=240)
resized.get_frame(0)
print("QTGMC_FRAME_OK")
print("NNEDI3_RESAMPLE_FRAME_OK")
'@
    $smokeOutput = @($smokeCode | & $VSPython - 2>&1)
    $smokeExitCode = $LASTEXITCODE
    $smokeOutput | ForEach-Object { Write-Host "        $_" }
    if ($smokeExitCode -eq 0 -and $smokeOutput -contains 'QTGMC_FRAME_OK' -and $smokeOutput -contains 'NNEDI3_RESAMPLE_FRAME_OK') {
        $ok.Add('runtime_smoke')
        Write-Host '      [OK] Synthetic restoration frames rendered.'
    } else {
        $failed.Add('runtime_smoke')
        Write-Host '      [FAIL] Synthetic restoration frame smoke failed.'
    }
}

Write-Host ''
Write-Host '======================================================================'
Write-Host "  VERIFIED: $($ok.Count) install action(s)"
if ($failed.Count -gt 0) {
    $uniqueFailed = @($failed | Select-Object -Unique)
    Write-Host "  FAILED:   $($uniqueFailed -join ', ')"
    Write-Host '======================================================================'
    exit 2
}
Write-Host '  BASE PLUGIN STACK: READY'
Write-Host '  MLRT: separate Full-only install stage'
Write-Host '======================================================================'
exit 0
