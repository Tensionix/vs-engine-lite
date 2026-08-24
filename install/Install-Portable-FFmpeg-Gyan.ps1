[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('full', 'full-shared')]
    [string]$Variant,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(?:auto|[0-9]+(?:\.[0-9]+)+)$')]
    [string]$ReleaseVersion,

    [Parameter(Mandatory = $true)]
    [string]$SevenZipPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Headers = @{ 'User-Agent' = 'Audion-VS-Engine-Lite' }
# A token lifts the GitHub limit from 60 requests an hour to 5000; without one
# a full pattern run exhausts it and downloads start failing halfway.
if ($env:GITHUB_TOKEN) { $Headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }
$ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
$PartPath = "$ArchivePath.part"
$HashPath = "$ArchivePath.sha256"
$MetadataPath = "$ArchivePath.source.json"
$ConnectTimeoutSeconds = 10
$TransferTimeoutSeconds = 60
$LowSpeedTimeoutSeconds = 15
$LowSpeedLimitBytes = 65536
$RetryCount = 1
$LegacyStableRelease = '7.1'
# 8.0.1 выбрана намеренно, а не по забывчивости. Её заголовки NVENC
# (ffnvcodec n13.0.19.0) требуют драйвер 570.0, и это покрывает самый
# населённый диапазон - примерно с 571 по 609. Ветка 610+ стоит у считанных
# единиц, а 8.1.2 и 9.x требуют именно её.
#
# Поставить последнюю версию значит заявить аппаратное ускорение NVIDIA и не
# дать его большинству тех, кому оно обещано. Обновлять эту константу имеет
# смысл тогда, когда 610-й драйвер станет массовым, а не когда выйдет
# следующий FFmpeg.
$CurrentStableRelease = '8.0.1'
$LegacyStableMinimumDriver = [version]'551.76'
$CurrentStableMinimumDriver = [version]'570.0'
$LatestStableMinimumDriver = [version]'610.0'

function ConvertTo-ResponseText {
    param($Content)
    if ($Content -is [byte[]]) {
        return [Text.Encoding]::UTF8.GetString($Content)
    }
    return [string]$Content
}

function Get-LatestGyanReleaseVersion {
    $repo = 'https://github.com/GyanD/codexffmpeg'
    $response = $null
    try {
        $response = Invoke-WebRequest -Headers $Headers -Uri "$repo/releases/latest" -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
    } catch {
        $response = $_.Exception.Response
    }
    $location = $null
    if ($response) {
        if ($response.Headers.Location) {
            $location = [string]$response.Headers.Location
        } elseif ($response.Headers['Location']) {
            $location = [string]$response.Headers['Location']
        }
    }
    if ($location -match '/tag/(?<tag>[0-9]+(?:\.[0-9]+)+)$') {
        Write-Host "[INFO] Resolved Gyan release through releases/latest redirect: $($Matches.tag)"
        return $Matches.tag
    }

    try {
        $versionResponse = Invoke-WebRequest -Headers $Headers -Uri 'https://www.gyan.dev/ffmpeg/builds/release-version' -TimeoutSec 30 -UseBasicParsing
        $text = (ConvertTo-ResponseText $versionResponse.Content).Trim()
        if ($text -match '^[0-9]+(?:\.[0-9]+)+$') {
            Write-Host "[INFO] Resolved Gyan release through official release-version endpoint: $text"
            return $text
        }
        throw "Unexpected Gyan release-version response: $text"
    } catch {
        Write-Warning "Direct Gyan release resolve failed; using GitHub API fallback: $($_.Exception.Message)"
    }

    $release = Invoke-RestMethod -Headers $Headers -Uri 'https://api.github.com/repos/GyanD/codexffmpeg/releases/latest' -TimeoutSec 30
    if ([string]$release.tag_name -notmatch '^[0-9]+(?:\.[0-9]+)+$') { throw "Unexpected Gyan GitHub release tag: $($release.tag_name)" }
    Write-Host "[INFO] Resolved Gyan release through GitHub API fallback: $($release.tag_name)"
    return [string]$release.tag_name
}

function Get-NvidiaDriverState {
    $present = $false
    try {
        $present = [bool](Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1)
    } catch {
        Write-Warning "Could not query video controllers: $($_.Exception.Message)"
    }
    $driver = ''
    $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    $smiPath = if ($smi) { $smi.Source } else { Join-Path $env:SystemRoot 'System32\nvidia-smi.exe' }
    if (Test-Path -LiteralPath $smiPath -PathType Leaf) {
        $raw = & $smiPath --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1
        if ([string]$raw -match '([0-9]+(?:\.[0-9]+)+)') {
            $driver = $Matches[1]
            $present = $true
        }
    }
    return [pscustomobject]@{ Present = $present; Driver = $driver }
}

if ($ReleaseVersion -eq 'auto') {
    $nvidia = Get-NvidiaDriverState

    if ($nvidia.Present -and -not $nvidia.Driver) {
        throw 'NVIDIA GPU detected but the driver version is unavailable; stable NVENC compatibility cannot be verified.'
    } elseif ($nvidia.Present) {
        $parsedDriver = [version]$nvidia.Driver

        if ($parsedDriver -lt $LegacyStableMinimumDriver) {
            throw "NVIDIA driver $($nvidia.Driver) is below $LegacyStableMinimumDriver. No supported automatic FFmpeg/NVENC branch is defined for this driver."
        } elseif ($parsedDriver -lt $CurrentStableMinimumDriver) {
            $ReleaseVersion = $LegacyStableRelease
            Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting Gyan FFmpeg $ReleaseVersion Stable (NVENC SDK 11.1)."
        } elseif ($parsedDriver -lt $LatestStableMinimumDriver) {
            $ReleaseVersion = $CurrentStableRelease
            Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting Gyan FFmpeg $ReleaseVersion Stable (NVENC API 13.0)."
        } else {
            $ReleaseVersion = Get-LatestGyanReleaseVersion
            Write-Host "[POLICY] NVIDIA driver $($nvidia.Driver): selecting latest Gyan Stable $ReleaseVersion (NVENC API 13.1+)."
        }
    } else {
        $ReleaseVersion = Get-LatestGyanReleaseVersion
        Write-Host "[POLICY] NVIDIA GPU not detected; selecting latest Gyan Stable $ReleaseVersion."
    }
}

$requiredDriver = if ([version]$ReleaseVersion -lt [version]'8.0') {
    $LegacyStableMinimumDriver
} elseif ([version]$ReleaseVersion -lt [version]'8.1') {
    $CurrentStableMinimumDriver
} else {
    $LatestStableMinimumDriver
}
$nvidiaForSelectedRelease = Get-NvidiaDriverState
if ($nvidiaForSelectedRelease.Present) {
    if (-not $nvidiaForSelectedRelease.Driver) {
        throw 'NVIDIA GPU detected but the driver version is unavailable; selected release compatibility cannot be verified.'
    }
    if ([version]$nvidiaForSelectedRelease.Driver -lt $requiredDriver) {
        throw "NVIDIA driver $($nvidiaForSelectedRelease.Driver) is below $requiredDriver required by Gyan FFmpeg $ReleaseVersion Stable."
    }
}
Write-Host "[RELEASE] Gyan Stable $ReleaseVersion ($Variant)"

function Test-SevenZipArchive([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    & $SevenZipPath t $Path *> $null
    return $LASTEXITCODE -eq 0
}

function Get-CachedHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $line = (Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue)
    if ($line -match '(?i)\b([0-9a-f]{64})\b') { return $Matches[1].ToLowerInvariant() }
    return ''
}

function Test-VerifiedCache {
    if (-not (Test-SevenZipArchive $ArchivePath)) { return $false }
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { return $false }
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    } catch {
        return $false
    }
    if ([string]$metadata.release_version -ne $ReleaseVersion -or [string]$metadata.variant -ne $Variant) { return $false }
    $expected = Get-CachedHash $HashPath
    if (-not $expected) { return $false }
    $actual = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    return $actual -eq $expected
}

function Invoke-CurlDownload([string]$Url, [switch]$IPv4) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return $false }
    Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
    $args = @(
        '--location', '--fail', '--silent', '--show-error',
        '--retry', $RetryCount, '--retry-delay', '2', '--retry-all-errors',
        '--retry-max-time', $TransferTimeoutSeconds,
        '--connect-timeout', $ConnectTimeoutSeconds, '--max-time', $TransferTimeoutSeconds,
        '--speed-time', $LowSpeedTimeoutSeconds, '--speed-limit', $LowSpeedLimitBytes,
        '--output', $PartPath, $Url
    )
    if ($IPv4) { $args = @('--ipv4') + $args }
    & $curl.Source @args
    return $LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $PartPath -PathType Leaf)
}

function Invoke-PowerShellDownload([string]$Url) {
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
            Invoke-WebRequest -Headers $Headers -Uri $Url -OutFile $PartPath -TimeoutSec $TransferTimeoutSeconds -UseBasicParsing
            if (Test-Path -LiteralPath $PartPath -PathType Leaf) { return $true }
        } catch {
            Write-Warning "PowerShell download attempt $attempt failed: $($_.Exception.Message)"
            Start-Sleep -Seconds ([Math]::Min(10, 2 * $attempt))
        }
    }
    return $false
}

$directName = if ($Variant -eq 'full-shared') { "ffmpeg-$ReleaseVersion-full_build-shared.7z" } else { "ffmpeg-$ReleaseVersion-full_build.7z" }
$directUrl = "https://www.gyan.dev/ffmpeg/builds/packages/$directName"
$githubUrl = "https://github.com/GyanD/codexffmpeg/releases/download/$ReleaseVersion/$directName"
$expectedHash = ''
Write-Host "[MIRROR] Gyan GitHub release URL resolved without API: $directName"

try {
    $checksumResponse = Invoke-WebRequest -Headers $Headers -Uri "$directUrl.sha256" -TimeoutSec 15 -UseBasicParsing
    $checksumText = ConvertTo-ResponseText $checksumResponse.Content
    if ($checksumText -match '(?i)\b([0-9a-f]{64})\b') {
        $expectedHash = $Matches[1].ToLowerInvariant()
        Write-Host '[HASH] Resolved through the official Gyan checksum endpoint.'
    }
} catch {
    Write-Warning "Gyan checksum endpoint unavailable; using GitHub API only for digest fallback: $($_.Exception.Message)"
}

if (-not $expectedHash) {
    try {
        $release = Invoke-RestMethod -Headers $Headers -Uri "https://api.github.com/repos/GyanD/codexffmpeg/releases/tags/$ReleaseVersion" -TimeoutSec 60
        $asset = $release.assets | Where-Object { $_.name -eq $directName } | Select-Object -First 1
        if ($asset) {
            if ($asset.browser_download_url) { $githubUrl = [string]$asset.browser_download_url }
            if ([string]$asset.digest -match '(?i)^sha256:([0-9a-f]{64})$') {
                $expectedHash = $Matches[1].ToLowerInvariant()
                Write-Host '[HASH] Resolved through GitHub API fallback.'
            }
        }
    } catch {
        Write-Warning "Gyan GitHub digest fallback unavailable: $($_.Exception.Message)"
    }
}
if (Test-VerifiedCache) {
    Write-Host "[CACHE] Using verified Gyan $ReleaseVersion $Variant archive: $ArchivePath"
    exit 0
}

$candidates = @()
if ($githubUrl) {
    $candidates += [pscustomobject]@{ Name = 'Gyan official GitHub mirror'; Url = $githubUrl }
}
$candidates += [pscustomobject]@{ Name = 'Gyan direct'; Url = $directUrl }

foreach ($candidate in $candidates) {
    $transports = @()
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) { $transports += 'curl-ipv4' }
    $transports += 'powershell'
    foreach ($transport in $transports) {
        Write-Host "[DOWNLOAD] $($candidate.Name) via $transport"
        Write-Host "[URL] $($candidate.Url)"
        $downloaded = switch ($transport) {
            'curl' { Invoke-CurlDownload $candidate.Url }
            'curl-ipv4' { Invoke-CurlDownload $candidate.Url -IPv4 }
            default { Invoke-PowerShellDownload $candidate.Url }
        }
        if (-not $downloaded) { continue }
        if (-not (Test-SevenZipArchive $PartPath)) {
            Write-Warning 'Downloaded payload failed 7-Zip integrity test.'
            Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $PartPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expectedHash -and $actualHash -ne $expectedHash) {
            Write-Warning "SHA-256 mismatch: expected $expectedHash, got $actualHash"
            Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
            continue
        }
        Move-Item -LiteralPath $PartPath -Destination $ArchivePath -Force
        Set-Content -LiteralPath $HashPath -Value $actualHash -Encoding Ascii
        [pscustomobject]@{
            provider = 'Gyan'
            release_version = $ReleaseVersion
            variant = $Variant
            asset = $directName
            sha256 = $actualHash
        } | ConvertTo-Json | Set-Content -LiteralPath $MetadataPath -Encoding UTF8
        Write-Host "[OK] Download verified: $ArchivePath"
        Write-Host "[SHA256] $actualHash"
        exit 0
    }
}

Remove-Item -LiteralPath $PartPath -Force -ErrorAction SilentlyContinue
if (Test-VerifiedCache) {
    Write-Warning "Network providers failed; using last verified cached archive: $ArchivePath"
    exit 0
}

throw 'Gyan direct and official GitHub mirror downloads failed, and no verified cached archive is available.'
