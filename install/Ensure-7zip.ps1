<#
.SYNOPSIS
  Audion VS Engine - bootstrap official 7-Zip portable CLIs (7zr.exe + 7za.exe).

.DESCRIPTION
  Dot-source this file to use Ensure-7zr / Ensure-7za / Expand-7zArchive.

  Idempotently installs 7-Zip standalone binaries into system_core\7zip\.
  Build env steps [01]/[02] call this explicitly before Python setup:

    - 7zr.exe (~1.5 MB)  : 7z-only extractor; direct download from 7-zip.org
    - 7za.exe (~1.7 MB)  : universal CLI (zip / 7z / tar / gz / bz2 / xz);
                           extracted from official 7zXXXX-extra.7z using 7zr

  Why 7-Zip and not Expand-Archive:
    - Expand-Archive is .NET ZipArchive based; chokes on >2 GB ZIPs and is
      memory-hungry on big multi-GB extracts (VapourSynth portable, BtbN
      FFmpeg)
    - 7za handles every format we ship and is byte-stable across Windows
      builds, which matters for the portable invariant

  Bootstrap is single-fetch and cached: once 7za.exe lives in
  system_core\7zip\ it travels with the project (CLAUDE.md section 2.1).
#>

function Get-Audion7zipDir {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $d = Join-Path $ProjectRoot 'system_core\7zip'
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
    return $d
}

function Ensure-7zr {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $dir = Get-Audion7zipDir -ProjectRoot $ProjectRoot
    $exe = Join-Path $dir '7zr.exe'
    if (-not (Test-Path $exe)) {
        $headers = @{ 'User-Agent' = 'Audion-VS-Engine' }
        $oldP = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Headers $headers -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $exe
        } finally { $ProgressPreference = $oldP }
        if (-not (Test-Path $exe)) { throw "Failed to download 7zr.exe to $exe" }
    }
    return $exe
}

function Ensure-7za {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        # 7-Zip extras package version. Releases are infrequent and the .7z
        # layout (7za.exe at archive root) has been stable since 9.x.
        # Override only if 7-zip.org changes naming.
        [string]$ExtraVersion = '2501'
    )
    $dir = Get-Audion7zipDir -ProjectRoot $ProjectRoot
    $exe = Join-Path $dir '7za.exe'
    if (Test-Path $exe) { return $exe }

    $r = Ensure-7zr -ProjectRoot $ProjectRoot

    $headers   = @{ 'User-Agent' = 'Audion-VS-Engine' }
    $extraName = "7z$ExtraVersion-extra.7z"
    $extraUrl  = "https://www.7-zip.org/a/$extraName"
    $extraPath = Join-Path $dir $extraName

    if (-not (Test-Path $extraPath)) {
        $oldP = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Headers $headers -Uri $extraUrl -OutFile $extraPath
        } finally { $ProgressPreference = $oldP }
    }

    # `e` = extract without preserving paths; pull just the bits we need
    & $r e $extraPath "-o$dir" '7za.exe' '7za.dll' -y -bso0 -bsp0 | Out-Null
    if (-not (Test-Path $exe)) {
        throw "7za.exe not found in $extraName after extraction (7-Zip extras layout changed?)"
    }
    Remove-Item -Path $extraPath -Force -ErrorAction SilentlyContinue
    return $exe
}

function Expand-7zArchive {
<#
.SYNOPSIS
  Universal extractor: dispatches to 7zr (.7z) or 7za (everything else).
.PARAMETER Archive
  Path to the archive (.zip / .7z / .tar.gz / etc.).
.PARAMETER Destination
  Output directory (created if missing).
.PARAMETER ProjectRoot
  Project root, used to bootstrap the 7-Zip CLI under system_core\7zip\.
#>
    param(
        [Parameter(Mandatory=$true)][string]$Archive,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )
    if (-not (Test-Path $Archive)) { throw "Archive not found: $Archive" }
    if (-not (Test-Path $Destination)) { New-Item -Path $Destination -ItemType Directory -Force | Out-Null }

    if ($Archive -match '\.7z(\.\d+)?$') {
        $exe = Ensure-7zr -ProjectRoot $ProjectRoot
    } else {
        $exe = Ensure-7za -ProjectRoot $ProjectRoot
    }
    # -aoa = overwrite all; -bso0 mute stdout listing; -bsp1 keep progress
    & $exe x "-o$Destination" $Archive -y -aoa -bso0 -bsp1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw ("{0} failed extracting {1} (exit {2})" -f [IO.Path]::GetFileName($exe), $Archive, $LASTEXITCODE)
    }
}
