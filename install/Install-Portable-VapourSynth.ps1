<#
.SYNOPSIS
  Audion VS Engine - Install portable VapourSynth into system_core\vapoursynth\

.DESCRIPTION
  Adapted from upstream Install-Portable-VapourSynth.ps1 (vapoursynth-team).
  Differences from upstream:
    - Target is fixed to project's system_core\vapoursynth\
    - Downloads land in project's install\download\
    - Default Python is 3.12 (matches orchestrator embedded runtime)
    - Unattended by default
    - Resolves "latest" VapourSynth via GitHub API /releases/latest
    - Does not pause; returns non-zero on failure for caller chaining

.PARAMETER ProjectRoot
  Absolute path to project root (where system_core\ lives).

.PARAMETER VSVersion
  Optional VapourSynth release tag (e.g. "R74"). If empty -> latest stable.

.PARAMETER PythonMinor
  Python 3.X minor. Default 12. The VS wheel uses cp312-abi3 (works on 3.12+).

.PARAMETER Force
  Deprecated compatibility switch. VapourSynth install always updates in place.
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [string]$VSVersion = "",
    [int]$PythonMinor = 12,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Universal 7-Zip extractor (replaces Expand-Archive: faster + reliable on
# >2 GB archives, no .NET ZipArchive memory pressure on the VS portable
# bundle which crosses 600 MB extracted).
. (Join-Path $PSScriptRoot 'Ensure-7zip.ps1')

# ---------- Paths ----------
$VSDir   = Join-Path $ProjectRoot 'system_core\vapoursynth'
$DLDir   = Join-Path $ProjectRoot 'install\download'
$Marker  = Join-Path $VSDir 'portable.vs'

if (-not (Test-Path $DLDir)) { New-Item -Path $DLDir -ItemType Directory -Force | Out-Null }

Write-Host "======================================================================"
Write-Host "  AUDION VS ENGINE - INSTALL PORTABLE VAPOURSYNTH"
Write-Host "======================================================================"
Write-Host "Project root: $ProjectRoot"
Write-Host "Target VS:    $VSDir"
Write-Host "Download dir: $DLDir"
Write-Host "Python:       3.$PythonMinor"
Write-Host ""

# ---------- Resolve VS version ----------
$Headers = @{ 'User-Agent' = 'Audion-VS-Engine' }
# A token lifts the GitHub limit from 60 requests an hour to 5000; without one
# a full pattern run exhausts it and downloads start failing halfway.
if ($env:GITHUB_TOKEN) { $Headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }
function Get-VSReleaseAssets($release) {
    $assets = @()
    if ($null -ne $release.assets) {
        $assets = @($release.assets | ForEach-Object { $_ })
    }
    if ($assets.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($release.assets_url)) {
        $assets = @(Invoke-RestMethod -Headers $Headers -Uri $release.assets_url | ForEach-Object { $_ })
    }
    return $assets
}

function Select-VSPortableAsset($release) {
    $assets = @(Get-VSReleaseAssets $release)
    $exactName = "VapourSynth64-Portable-$($release.tag_name).zip"

    $asset = @($assets | Where-Object { $_.name -eq $exactName } | Select-Object -First 1)
    if ($asset.Count -eq 0) {
        $asset = @($assets | Where-Object { $_.name -match '^VapourSynth64-Portable-.+\.zip$' } | Select-Object -First 1)
    }
    if ($asset.Count -gt 0) { return $asset[0] }

    return $null
}

function Get-VSWebRelease([string]$Tag) {
    $expandedUri = "https://github.com/vapoursynth/vapoursynth/releases/expanded_assets/$([uri]::EscapeDataString($Tag))"
    $html = (Invoke-WebRequest -Headers $Headers -Uri $expandedUri -TimeoutSec 30).Content
    $pattern = 'href="(?<href>/vapoursynth/vapoursynth/releases/download/[^\"]+)"'
    $assets = @(
        [regex]::Matches($html, $pattern) | ForEach-Object {
            $href = $_.Groups['href'].Value
            [pscustomobject]@{
                name                 = [uri]::UnescapeDataString((Split-Path $href -Leaf))
                browser_download_url = "https://github.com$href"
            }
        }
    )
    [pscustomobject]@{
        tag_name   = $Tag
        draft      = $false
        prerelease = $false
        assets     = $assets
        assets_url = $null
    }
}

function Get-VSWebReleaseTags {
    $html = (Invoke-WebRequest -Headers $Headers -Uri 'https://github.com/vapoursynth/vapoursynth/releases' -TimeoutSec 30).Content
    @(
        [regex]::Matches($html, '/vapoursynth/vapoursynth/releases/tag/(?<tag>R[0-9]+)') |
            ForEach-Object { $_.Groups['tag'].Value } |
            Select-Object -Unique
    )
}

$VSAsset = $null

if ([string]::IsNullOrWhiteSpace($VSVersion)) {
    Write-Host "[1/7] Resolving latest VapourSynth portable release from GitHub..."
    try {
        $releases = @(Invoke-RestMethod -Headers $Headers -Uri 'https://api.github.com/repos/vapoursynth/vapoursynth/releases?per_page=20' | ForEach-Object { $_ })
        Write-Host "      [info] Resolved releases through GitHub API."
    } catch {
        Write-Host "      [warn] GitHub API unavailable, scanning release pages: $($_.Exception.Message)"
        $releases = @(
            foreach ($webTag in Get-VSWebReleaseTags) {
                try {
                    Get-VSWebRelease $webTag
                } catch {
                    Write-Host "      [skip] $webTag`: release assets page unavailable: $($_.Exception.Message)"
                }
            }
        )
    }
    foreach ($candidate in $releases) {
        if ($candidate.draft -or $candidate.prerelease) { continue }

        $candidateAsset = Select-VSPortableAsset $candidate
        if ($null -ne $candidateAsset) {
            $VSVersion = $candidate.tag_name
            $VSAsset = $candidateAsset
            break
        }

        Write-Host "      [skip] $($candidate.tag_name): no VapourSynth64-Portable ZIP asset"
    }

    if ($null -eq $VSAsset) {
        throw "Could not find a stable VapourSynth release with a VapourSynth64-Portable-*.zip asset"
    }
} else {
    Write-Host "[1/7] Resolving VapourSynth release $VSVersion from GitHub..."
    $tagForUrl = [uri]::EscapeDataString($VSVersion)
    try {
        $rel = Invoke-RestMethod -Headers $Headers -Uri "https://api.github.com/repos/vapoursynth/vapoursynth/releases/tags/$tagForUrl"
    } catch {
        Write-Host "      [warn] GitHub API unavailable, reading release page: $($_.Exception.Message)"
        $rel = Get-VSWebRelease $VSVersion
    }
    $VSAsset = Select-VSPortableAsset $rel

    if ($null -eq $VSAsset) {
        $availableAssets = @((Get-VSReleaseAssets $rel) | ForEach-Object { $_.name })
        if ($availableAssets.Count -eq 0) {
            $available = '(none)'
        } else {
            $available = ($availableAssets -join ', ')
        }
        throw "No VapourSynth64-Portable ZIP asset found for $VSVersion. Available assets: $available. Run without /R to select the latest stable release that actually has a portable ZIP."
    }
}

Write-Host "      VS version: $VSVersion"
Write-Host "      VS asset:   $($VSAsset.name)"

$VSAssetName = $VSAsset.name
$VSUrl       = $VSAsset.browser_download_url
if ([string]::IsNullOrWhiteSpace($VSUrl)) { throw "Selected VS asset has no browser_download_url: $VSAssetName" }
$VSZip       = Join-Path $DLDir $VSAssetName

# ---------- Resolve Python latest patch via HEAD probing ----------
Write-Host "[2/7] Resolving latest Python 3.$PythonMinor.x..."
$pyPatch = -1
for ($i = 0; $i -le 30; $i++) {
    $uri = "https://www.python.org/ftp/python/3.$PythonMinor.$i/python-3.$PythonMinor.$i-embed-amd64.zip"
    try {
        Invoke-WebRequest -Headers $Headers -Uri $uri -Method Head -TimeoutSec 10 | Out-Null
        $pyPatch = $i
    } catch {
        if ($pyPatch -ge 0) { break }
    }
}
if ($pyPatch -lt 0) { throw "Could not resolve any Python 3.$PythonMinor.x embed-amd64 build" }
$PyVer = "3.$PythonMinor.$pyPatch"
Write-Host "      Python: $PyVer"

$PyAssetName = "python-$PyVer-embed-amd64.zip"
$PyUrl       = "https://www.python.org/ftp/python/$PyVer/$PyAssetName"
$PyZip       = Join-Path $DLDir $PyAssetName
$GetPipUrl   = 'https://bootstrap.pypa.io/get-pip.py'
$GetPipPath  = Join-Path $DLDir 'get-pip.py'

# ---------- Download fresh artifacts ----------
$ProgressPreference = 'Continue'
function Get-Fresh($url, $dest, $label) {
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Force
    }
    Write-Host "      Downloading $label ..."
    Invoke-WebRequest -Headers $Headers -Uri $url -OutFile $dest
    $sz = (Get-Item $dest).Length
    Write-Host "      [OK]    $label  ($sz bytes)"
}
Write-Host "[3/7] Downloading artifacts..."
Get-Fresh $PyUrl     $PyZip      $PyAssetName
Get-Fresh $VSUrl     $VSZip      $VSAssetName
Get-Fresh $GetPipUrl $GetPipPath 'get-pip.py'

# ---------- Prepare target ----------
Write-Host "[4/7] Preparing target $VSDir ..."
if (Test-Path -LiteralPath $VSDir) {
    Write-Host "      [update] Cleaning existing VapourSynth target..."
    Get-ChildItem -LiteralPath $VSDir -Force | Remove-Item -Recurse -Force
} else {
    New-Item -Path $VSDir -ItemType Directory -Force | Out-Null
}

# ---------- Extract Python embed ----------
Write-Host "[5/7] Extracting Python embed..."
$ProgressPreference = 'SilentlyContinue'
Expand-7zArchive -Archive $PyZip -Destination $VSDir -ProjectRoot $ProjectRoot

# Patch ._pth: enable site-packages and vs-scripts on import path
$pthPath = Join-Path $VSDir "python3$PythonMinor._pth"
if (Test-Path $pthPath) {
    $existing = Get-Content $pthPath -Raw
    if ($existing -notmatch '\.\.\\presets')     { Add-Content -Path $pthPath -Encoding UTF8 -Value '..\presets' }
    if ($existing -notmatch 'vs-scripts')        { Add-Content -Path $pthPath -Encoding UTF8 -Value 'vs-scripts' }
    if ($existing -notmatch 'Lib\\site-packages'){ Add-Content -Path $pthPath -Encoding UTF8 -Value 'Lib\site-packages' }
    if ($existing -notmatch '^\s*import\s+site'){ Add-Content -Path $pthPath -Encoding UTF8 -Value 'import site' }
}

New-Item -Path (Join-Path $VSDir 'vs-scripts') -ItemType Directory -Force | Out-Null

# Bootstrap pip
$VSPython = Join-Path $VSDir 'python.exe'
Write-Host "      Bootstrapping pip..."
& $VSPython $GetPipPath '--no-warn-script-location' --quiet
if ($LASTEXITCODE -ne 0) { throw "get-pip.py failed (exit $LASTEXITCODE)" }
# Remove generated launcher .exe wrappers (upstream does this too)
Get-ChildItem -Path (Join-Path $VSDir 'Scripts') -Filter '*.exe' -ErrorAction SilentlyContinue | Remove-Item -Force

# ---------- Extract VapourSynth on top ----------
Write-Host "[6/7] Extracting VapourSynth..."
Expand-7zArchive -Archive $VSZip -Destination $VSDir -ProjectRoot $ProjectRoot

# Pick the right VSScript.dll for our Python version (3.12+ -> remove the 3.8 variant)
$vsscript38 = Join-Path $VSDir 'VSScriptPython38.dll'
if (Test-Path $vsscript38) {
    if ($PythonMinor -eq 8) {
        Move-Item -Path $vsscript38 -Destination (Join-Path $VSDir 'VSScript.dll') -Force
    } else {
        Remove-Item -Path $vsscript38 -Force
    }
}

# Install VapourSynth wheel into VS-host Python
Write-Host "      Installing VapourSynth Python wheel..."
$wheelDir = Join-Path $VSDir 'wheel'
if (-not (Test-Path $wheelDir)) { throw "wheel\ folder not found in extracted VS" }
$wheel = Get-ChildItem $wheelDir -Filter 'VapourSynth-*-cp*-abi3-win_amd64.whl' | Select-Object -First 1
if (-not $wheel) {
    # Older builds may ship per-version wheels
    $wheel = Get-ChildItem $wheelDir -Filter "VapourSynth-*-cp3$PythonMinor-cp3$PythonMinor-win_amd64.whl" | Select-Object -First 1
}
if (-not $wheel) { throw "No suitable VapourSynth wheel found in $wheelDir" }
& $VSPython -m pip install $wheel.FullName --quiet --no-warn-script-location
if ($LASTEXITCODE -ne 0) { throw "pip install VapourSynth wheel failed (exit $LASTEXITCODE)" }

# VS R74+ with the Python wheel layout auto-loads plugins from
# vapoursynth.get_plugin_dir(), not the legacy VSDir\vs-plugins folder.
# Create the active path explicitly so later plugin installers and humans see
# the same directory.
$pluginDirProbe = (& $VSPython -c "import vapoursynth; print(vapoursynth.get_plugin_dir())" 2>$null | Select-Object -Last 1)
if ([string]::IsNullOrWhiteSpace($pluginDirProbe)) {
    $ActivePluginDir = Join-Path $VSDir 'Lib\site-packages\vapoursynth\plugins'
} else {
    $ActivePluginDir = $pluginDirProbe.Trim()
}
New-Item -Path $ActivePluginDir -ItemType Directory -Force | Out-Null
Write-Host "      Active VS plugin dir: $ActivePluginDir"

# ---------- Repair pip-generated shim shebangs ----------
# pip embeds an absolute shebang into Scripts\*.exe at install time. After any later
# project move that path is dead and the shim exits silently with code 1. Rewrite the
# embedded shebang to the current $VSPython right now, and ship a standalone
# Repair-PipShims.{cmd,ps1} so users can re-run it after future moves without
# reinstalling the whole stack. (See MEMORY.md gotcha "pip launcher shebang".)
$RepairScript = Join-Path $PSScriptRoot 'Repair-PipShims.ps1'
$ScriptsDir   = Join-Path $VSDir 'Scripts'
if ((Test-Path $RepairScript) -and (Test-Path $ScriptsDir)) {
    Write-Host "      Repairing pip shim shebangs to $VSPython ..."
    & $RepairScript -ScriptsDir $ScriptsDir -PyExe $VSPython
    if ($LASTEXITCODE -ne 0) { throw "Repair-PipShims failed (exit $LASTEXITCODE)" }
} else {
    Write-Host "      [warn] Repair-PipShims.ps1 not found alongside this installer; skipping shim repair."
}

# Drop install marker
Set-Content -Path $Marker -Value "$VSVersion`r`nPython=$PyVer`r`nInstalled=$(Get-Date -Format o)" -Encoding UTF8

# ---------- Smoke test ----------
Write-Host "[7/7] Smoke test..."
# After wheel install + shim repair the canonical vspipe lives in Scripts\
$VSPipe = Join-Path $VSDir 'Scripts\vspipe.exe'
if (-not (Test-Path $VSPipe)) {
    # Fallback: some upstream layouts ship a native vspipe at root
    $VSPipe = Join-Path $VSDir 'vspipe.exe'
}
if (-not (Test-Path $VSPipe)) { throw "vspipe.exe not found at $VSDir or $VSDir\Scripts" }
& $VSPipe --version
if ($LASTEXITCODE -ne 0) { throw "vspipe --version failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "[SUCCESS] VapourSynth $VSVersion installed at $VSDir"
Write-Host "          VS-host Python: $PyVer"
Write-Host ""
exit 0
