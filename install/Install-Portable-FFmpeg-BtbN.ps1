<#
.SYNOPSIS
  Audion VS Engine Lite - install portable BtbN FFmpeg into Tools\ffmpeg.

.DESCRIPTION
  Adapted from Audion VS Engine Lite's working FFmpeg installer.
  Resolves the selected win64 FFmpeg build, extracts to Tools\ffmpeg,
  exposes bin\ffmpeg.exe and bin\ffprobe.exe.

  Master/nightly assets are never selected. Source Auto = BtbN release branch
  first, Gyan.dev fallback if BtbN changes release layout or download fails. Builder uses this file as the BtbN entry;
  Gyan also remains available as its own separate CMD installer.
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [switch]$Force,
    [ValidateSet('gpl','lgpl','gpl-shared','lgpl-shared')]
    [string]$Variant = 'gpl',
    [ValidateSet('Auto','BtbN','Gyan')]
    [string]$Source = 'BtbN',
    [switch]$AllowRollingBranch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'Ensure-7zip.ps1')

$Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$FFDir = Join-Path $Root 'Tools\ffmpeg'
$DLDir = Join-Path $Root 'install\download'
$Marker = Join-Path $FFDir '.audion-ffmpeg.marker'
$ProviderFallbackExitCode = 20
if (-not $AllowRollingBranch -and $Source -ne 'Gyan') {
    Write-Warning 'BtbN publishes rolling release-branch heads, not binaries built from exact FFmpeg stable tags. Exact-stable policy is active; requesting the Gyan stable provider.'
    exit $ProviderFallbackExitCode
}
if ($AllowRollingBranch -and $Source -ne 'Gyan') {
    Write-Warning 'Explicit emergency mode enabled: a rolling BtbN release-branch build may be newer than the last exact FFmpeg stable tag.'
}
$Headers = @{ 'User-Agent' = 'Audion-VS-Engine-Lite' }
# A token lifts the GitHub limit from 60 requests an hour to 5000; without one
# a full pattern run exhausts it and downloads start failing halfway.
if ($env:GITHUB_TOKEN) { $Headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }
Write-Host '[PRECHECK] Ensuring portable 7-Zip before FFmpeg policy selection...'
$SevenZipPath = Ensure-7za -ProjectRoot $Root
Write-Host "[PRECHECK] 7-Zip ready: $SevenZipPath"

$LegacyReleaseSeries = '7.1'
$CurrentReleaseSeries = '8.0'
$LatestReleaseSeries = '8.1'
$LegacyStableMinimumDriver = [version]'471.41'
$CurrentStableMinimumDriver = [version]'570.0'
$LatestStableMinimumDriver = [version]'610.0'
$UnsupportedDriverExitCode = 21
$PreferredStableSeries = $LatestReleaseSeries

function Get-NvidiaDriverState {
    $present = $false
    try {
        $present = [bool](Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match 'NVIDIA' } |
            Select-Object -First 1)
    } catch {
        Write-Warning "Could not query video controllers: $($_.Exception.Message)"
    }

    $driver = ''
    $nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    $nvidiaSmiPath = if ($nvidiaSmi) {
        $nvidiaSmi.Source
    } else {
        Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    }

    if (Test-Path -LiteralPath $nvidiaSmiPath -PathType Leaf) {
        $rawDriver = & $nvidiaSmiPath --query-gpu=driver_version --format=csv,noheader 2>$null |
            Select-Object -First 1
        if ([string]$rawDriver -match '([0-9]+(?:\.[0-9]+)+)') {
            $driver = $Matches[1]
            $present = $true
        }
    }

    return [pscustomobject]@{
        Present = $present
        Driver = $driver
    }
}

$nvidia = Get-NvidiaDriverState
if ($nvidia.Present) {
    if (-not $nvidia.Driver) {
        Write-Warning 'NVIDIA GPU detected, but the driver version is unavailable; stable NVENC compatibility cannot be verified.'
        exit $UnsupportedDriverExitCode
    }

    $parsedDriver = [version]$nvidia.Driver
    if ($parsedDriver -lt $LegacyStableMinimumDriver) {
        Write-Warning "NVIDIA driver $($nvidia.Driver) is below $LegacyStableMinimumDriver. No supported automatic NVENC branch is defined."
        exit $UnsupportedDriverExitCode
    }

    if ($parsedDriver -lt $CurrentStableMinimumDriver) {
        $PreferredStableSeries = $LegacyReleaseSeries
        Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting BtbN $PreferredStableSeries compatible release branch."
    } elseif ($parsedDriver -lt $LatestStableMinimumDriver) {
        $PreferredStableSeries = $CurrentReleaseSeries
        Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting BtbN $PreferredStableSeries compatible release branch."
    } else {
        $PreferredStableSeries = $LatestReleaseSeries
        Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting BtbN $PreferredStableSeries compatible release branch."
    }
} else {
    Write-Host "NVIDIA GPU: not detected; selecting BtbN $PreferredStableSeries release branch without an NVENC driver gate."
}

if (-not (Test-Path $DLDir)) { New-Item -Path $DLDir -ItemType Directory -Force | Out-Null }

Write-Host "======================================================================"
Write-Host "  AUDION VS ENGINE LITE - INSTALL PORTABLE FFMPEG BTBN"
Write-Host "======================================================================"
Write-Host "Project root: $Root"
Write-Host "Target:       $FFDir"
Write-Host "Variant:      $Variant"
Write-Host "Source:       $Source"
Write-Host ""

function Get-UpstreamFFmpegStableVersion {
    param([Parameter(Mandatory=$true)][string]$Series)

    try {
        $response = Invoke-WebRequest -Headers $Headers -Uri 'https://ffmpeg.org/download.html' -TimeoutSec 30
        $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
        $escapedSeries = [Regex]::Escape($Series)
        $versions = [regex]::Matches($text, "(?i)\bFFmpeg\s+(?<version>$escapedSeries(?:\.\d+)?)\b") |
            ForEach-Object { [version]$_.Groups['version'].Value } |
            Sort-Object -Descending -Unique
        return $versions | Select-Object -First 1
    } catch {
        Write-Verbose "Could not resolve upstream FFmpeg stable version for ${Series}: $($_.Exception.Message)"
        return $null
    }
}

function Resolve-BtbNFFmpegAsset {
    param(
        [Parameter(Mandatory=$true)][string]$Variant,
        [string]$PreferredSeries = ''
    )

    Write-Host "[1/4] Resolving BtbN FFmpeg compatible release branch..."
    $repoUrl = 'https://github.com/BtbN/FFmpeg-Builds'
    $escapedVariant = [Regex]::Escape($Variant)
    $assetRegex = "^ffmpeg-n(?<build>.+)-win64-$escapedVariant-(?<series>[0-9]+(?:\.[0-9]+)+)\.zip$"
    $selectedRelease = $null

    try {
        # Invoke-RestMethod deliberately emits a top-level JSON array as one object in
        # recent PowerShell versions. Direct assignment preserves normal foreach
        # enumeration; wrapping the call in @() can leave a nested Object[].
        $releases = Invoke-RestMethod -Headers $Headers -Uri 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases?per_page=100' -TimeoutSec 60
        $releaseAssets = foreach ($release in $releases) {
            foreach ($item in @($release.assets)) {
                if ($item.name -match $assetRegex -and [string]$Matches.series -eq $PreferredSeries) {
                    $buildText = [string]$Matches.build
                    $buildVersionMatch = [regex]::Match($buildText, '^(?<version>[0-9]+(?:\.[0-9]+){1,2})')
                    if (-not $buildVersionMatch.Success) { continue }
                    [pscustomobject]@{
                        Asset = $item
                        Branch = [version]$Matches.series
                        BuildVersion = [version]$buildVersionMatch.Groups['version'].Value
                        Tag = [string]$release.tag_name
                        Published = [datetime](@($release.published_at)[0])
                    }
                }
            }
        }
        $selectedRelease = $releaseAssets | Sort-Object Published -Descending | Select-Object -First 1
    } catch {
        Write-Warning "GitHub API history is unavailable; using the direct BtbN compatibility table. $($_.Exception.Message)"
    }

    if (-not $selectedRelease) {
        $tag = 'latest'
        $assetName = "ffmpeg-n$PreferredSeries-latest-win64-$Variant-$PreferredSeries.zip"
        if ($PreferredSeries -eq '8.0') {
            $tag = 'autobuild-2026-02-28-12-59'
            $assetName = "ffmpeg-n8.0.1-66-g27b8d1a017-win64-$Variant-8.0.zip"
        }
        $url = "$repoUrl/releases/download/$tag/$assetName"
        $head = Invoke-WebRequest -Headers $Headers -Uri $url -Method Head -TimeoutSec 30
        $selectedRelease = [pscustomobject]@{
            Asset = [pscustomobject]@{
                name = $assetName
                size = @($head.Headers['Content-Length'])[0]
                browser_download_url = $url
            }
            Branch = [version]$PreferredSeries
            BuildVersion = if ($PreferredSeries -eq '8.0') { [version]'8.0.1' } else { [version]$PreferredSeries }
            Tag = $tag
            Published = [datetime]::MinValue
        }
    }

    $asset = $selectedRelease.Asset
    $tag = $selectedRelease.Tag
    Write-Host "      Release tag: $tag"
    Write-Host "      FFmpeg branch: $($selectedRelease.Branch)"
    if ($tag -ne 'latest') {
        $upstreamStable = Get-UpstreamFFmpegStableVersion -Series $PreferredSeries
        if ($upstreamStable -and $selectedRelease.BuildVersion -lt $upstreamStable) {
            Write-Warning "BtbN does not publish current upstream FFmpeg $upstreamStable for branch $PreferredSeries. Latest available compatible BtbN build is based on $($selectedRelease.BuildVersion); keeping branch $PreferredSeries to preserve NVENC driver compatibility."
        }
    }
    $assetSize = $asset.size
    if (-not $assetSize) {
        $assetSize = @((Invoke-WebRequest -Headers $Headers -Uri $asset.browser_download_url -Method Head -TimeoutSec 30).Headers['Content-Length'])[0]
    }

    $checksumUrl = "$repoUrl/releases/download/$tag/checksums.sha256"
    $checksumResponse = Invoke-WebRequest -Headers $Headers -Uri $checksumUrl -TimeoutSec 30
    $checksumText = if ($checksumResponse.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($checksumResponse.Content) } else { [string]$checksumResponse.Content }
    $escapedName = [Regex]::Escape([string]$asset.name)
    $hashMatch = [regex]::Match($checksumText, "(?im)^\s*(?<hash>[0-9a-f]{64})\s+\*?$escapedName\s*$")
    if (-not $hashMatch.Success) {
        throw "Official BtbN checksum is missing for $($asset.name) in $tag."
    }
    $expectedHash = $hashMatch.Groups['hash'].Value.ToLowerInvariant()

    return [pscustomobject]@{
        Source = 'BtbN'
        Release = "ffmpeg-$($selectedRelease.Branch)"
        BuildVersion = [string]$selectedRelease.BuildVersion
        Tag = $tag
        Name = $asset.name
        Size = $assetSize
        Url = $asset.browser_download_url
        Sha256 = $expectedHash
    }
}

function Resolve-GyanFFmpegAsset {
    param([Parameter(Mandatory=$true)][string]$Variant)

    Write-Host "[1/4] Resolving Gyan.dev FFmpeg release..."
    $name = switch ($Variant) {
        'gpl'         { 'ffmpeg-release-full.7z' }
        'gpl-shared'  { 'ffmpeg-release-full-shared.7z' }
        'lgpl'        { 'ffmpeg-release-full.7z' }
        'lgpl-shared' { 'ffmpeg-release-full-shared.7z' }
    }
    $url = "https://www.gyan.dev/ffmpeg/builds/$name"
    $head = Invoke-WebRequest -Headers $Headers -Uri $url -Method Head
    $size = $head.Headers['Content-Length']
    Write-Host "      Release: Gyan latest"

    return [pscustomobject]@{
        Source = 'Gyan'
        Release = 'gyan-latest'
        Name = $name
        Size = $size
        Url = $url
    }
}

function Try-DownloadFFmpegAsset {
    param([Parameter(Mandatory=$true)]$Candidate)

    Write-Host "      Asset:   $($Candidate.Name) ($($Candidate.Size) bytes)"
    Write-Host "      Source:  $($Candidate.Source)"
    $archivePath = Join-Path $DLDir $Candidate.Name
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    $oldP = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Headers $Headers -Uri $Candidate.Url -OutFile $archivePath
    } finally {
        $ProgressPreference = $oldP
    }
    if (-not (Test-Path -LiteralPath $archivePath)) {
        throw "Download finished but archive is missing: $archivePath"
    }
    if ($Candidate.PSObject.Properties.Name -contains 'Sha256' -and $Candidate.Sha256) {
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $Candidate.Sha256) {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
            throw "SHA-256 mismatch for $($Candidate.Name): expected $($Candidate.Sha256), got $actualHash"
        }
        Write-Host "      SHA-256: $actualHash [OK]"
    }
    return $archivePath
}

$primaryCandidate = $null
if ($Source -eq 'Gyan') {
    $primaryCandidate = Resolve-GyanFFmpegAsset -Variant $Variant
} else {
    try {
        $primaryCandidate = Resolve-BtbNFFmpegAsset -Variant $Variant -PreferredSeries $PreferredStableSeries
    } catch {
        if ($Source -eq 'BtbN') {
            Write-Warning "BtbN resolve failed; requesting Gyan Stable provider fallback: $($_.Exception.Message)"
            exit $ProviderFallbackExitCode
        }
        Write-Warning "BtbN resolve failed: $($_.Exception.Message)"
        $primaryCandidate = Resolve-GyanFFmpegAsset -Variant $Variant
    }
}

$ArchivePath = $null
$Selected = $primaryCandidate
$Tmp = Join-Path $Root 'system_core\_ffmpeg_btbn_tmp'

Write-Host "[2/4] Downloading..."
try {
    $ArchivePath = Try-DownloadFFmpegAsset -Candidate $Selected
} catch {
    if ($Source -eq 'BtbN' -and $Selected.Source -eq 'BtbN') {
        Write-Warning "BtbN download failed; requesting Gyan Stable provider fallback: $($_.Exception.Message)"
        exit $ProviderFallbackExitCode
    }
    if ($Source -ne 'Auto' -or $Selected.Source -eq 'Gyan') { throw }
    Write-Warning "BtbN download failed: $($_.Exception.Message)"
    Write-Host "      Falling back to Gyan.dev..."
    $Selected = Resolve-GyanFFmpegAsset -Variant $Variant
    $ArchivePath = Try-DownloadFFmpegAsset -Candidate $Selected
}
Write-Host "      [OK] downloaded fresh"

Write-Host "[3/4] Extracting..."
if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force }
New-Item -Path $Tmp -ItemType Directory -Force | Out-Null
Expand-7zArchive -Archive $ArchivePath -Destination $Tmp -ProjectRoot $Root

$inner = Get-ChildItem $Tmp -Directory | Select-Object -First 1
if (-not $inner) { throw "Extracted archive has no top-level folder" }

if (Test-Path -LiteralPath $FFDir) {
    Write-Host "      [update] cleaning existing FFmpeg target..."
    Get-ChildItem -LiteralPath $FFDir -Force | Remove-Item -Recurse -Force
} else {
    New-Item -Path $FFDir -ItemType Directory -Force | Out-Null
}

$innerItems = Get-ChildItem -LiteralPath $inner.FullName -Force
if (-not $innerItems) { throw "Extracted FFmpeg folder is empty" }
Move-Item -LiteralPath $innerItems.FullName -Destination $FFDir -Force
Remove-Item -LiteralPath $Tmp -Recurse -Force

# Corresponding Source: версия и коммит читаются из README, который только что
# лёг рядом с бинарником, - здесь ничего не зашито.
$sourceHelper = Join-Path $PSScriptRoot 'Fetch-FFmpegSource.ps1'
if (Test-Path -LiteralPath $sourceHelper) {
    & $sourceHelper -ProjectRoot $Root
}

Write-Host "[4/4] Smoke test..."
$ffmpeg = Join-Path $FFDir 'bin\ffmpeg.exe'
$ffprobe = Join-Path $FFDir 'bin\ffprobe.exe'
if (-not (Test-Path $ffmpeg)) { throw "ffmpeg.exe missing at $ffmpeg" }
if (-not (Test-Path $ffprobe)) { throw "ffprobe.exe missing at $ffprobe" }

try {
    $verLine = (& $ffmpeg -hide_banner -version | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg -version failed with exit code $LASTEXITCODE" }
} catch {
    Write-Host ""
    Write-Host "[ERROR] FFmpeg payload was extracted, but Windows blocked ffmpeg.exe during smoke test."
    Write-Host "        This is App Control / Smart App Control policy, not an archive extraction failure."
    Write-Host "        Blocked executable: $ffmpeg"
    Write-Host "        If this same BtbN build works in another project tree, compare trust/allow rules for that path."
    throw
}
Write-Host "      $verLine"

if ($nvidia.Present) {
    Write-Host "      NVENC: running hardware encoder smoke test..."
    & $ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=size=256x256:rate=1' -frames:v 1 -c:v h264_nvenc -f null NUL
    if ($LASTEXITCODE -ne 0) {
        throw "BtbN $($Selected.Release) failed the NVENC smoke test with exit code $LASTEXITCODE."
    }
    Write-Host "      NVENC: [OK]"
}

Set-Content -Path $Marker -Value "$($Selected.Release)`r`nSource=$($Selected.Source)`r`nAsset=$($Selected.Name)`r`nVariant=$Variant`r`nInstalled=$(Get-Date -Format o)" -Encoding UTF8

Write-Host ""
Write-Host "[SUCCESS] FFmpeg BtbN ($Variant) installed at $FFDir"
Write-Host "          ffmpeg:  $ffmpeg"
Write-Host "          ffprobe: $ffprobe"
exit 0
