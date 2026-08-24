<#
.SYNOPSIS
  Audion VS Engine - smoke-bench every preset (palette x preset matrix).

.DESCRIPTION
  Walks system_core\presets\{precision,film_looks,retro,restoration}\*.vpy
  and runs each through:

      vspipe -c y4m --end <Frames-1> <preset.vpy> - 2>nul
        | ffmpeg -hide_banner -loglevel error -y -i - -f null -

  Pipe goes through cmd.exe so the inter-process channel is a real shell
  pipe (PowerShell native pipe between two natives serialises through the
  host -- much slower).

  This is a SMOKE bench: short clip (default 30 frames), no encode, just
  proves each preset:
    - parses (vspipe --info-equivalent loading succeeds)
    - resolves all plugin namespaces it needs
    - delivers frames to ffmpeg without raising

  Wall-time per preset is reported but is not a quality metric -- TensorRT
  presets pay 30-120s engine-compile on first run per (model, GPU, res)
  combo, which dominates the bench number.

  All preset env vars default sensibly except AUDION_VS_INPUT which we set
  to the file you drag in. Optionally we sweep AUDION_VS_USE_CUDA on/off
  for Precision presets (the only palette wired to that switch).

.PARAMETER ProjectRoot
  Absolute path to project root.

.PARAMETER InputFile
  Source video (drag-n-drop friendly).

.PARAMETER Frames
  How many frames to render per preset (default 30). Lower = faster smoke,
  higher = more representative of real throughput.

.PARAMETER Cuda
  Drives AUDION_VS_USE_CUDA for Precision presets that branch on it.
  "off"   : every preset CPU
  "on"    : every preset CUDA (NVIDIA-only path)
  "sweep" : Precision presets BOTH modes; others as-is

.PARAMETER Palette
  Comma-separated palette filter, e.g. "restoration" or
  "precision,restoration". Default = all four palettes.

.PARAMETER ReportJson
  Optional path to write a JSON report (per-preset rows + summary).
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$InputFile,
    [int]$Frames = 30,
    [ValidateSet('off','on','sweep')][string]$Cuda = 'off',
    [string]$Palette = '',
    [string]$ReportJson = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputFile)) { throw "Input not found: $InputFile" }
$InputFile = (Resolve-Path $InputFile).Path

$VSPipe    = Join-Path $ProjectRoot 'system_core\vapoursynth\Scripts\vspipe.exe'
$FFmpeg    = Join-Path $ProjectRoot 'Tools\ffmpeg\bin\ffmpeg.exe'
$PresetDir = Join-Path $ProjectRoot 'system_core\presets'

foreach ($p in @($VSPipe, $FFmpeg, $PresetDir)) {
    if (-not (Test-Path $p)) { throw "Required component missing: $p" }
}

# ---------- Discover presets ----------
$palettes = 'precision','film_looks','retro','restoration'
if ($Palette) {
    $requested = $Palette.Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    $unknown = $requested | Where-Object { $palettes -notcontains $_ }
    if ($unknown) { throw "Unknown palette(s): $($unknown -join ', '). Valid: $($palettes -join ', ')" }
    $palettes = $requested
}

$presets  = @()
foreach ($pal in $palettes) {
    $palDir = Join-Path $PresetDir $pal
    if (-not (Test-Path $palDir)) { continue }
    Get-ChildItem -Path $palDir -Filter '*.vpy' -File | Sort-Object Name | ForEach-Object {
        $presets += [pscustomobject]@{
            Palette = $pal
            Name    = [IO.Path]::GetFileNameWithoutExtension($_.Name)
            Path    = $_.FullName
        }
    }
}

if ($presets.Count -eq 0) { throw "No presets discovered under $PresetDir (palettes: $($palettes -join ', '))" }

Write-Host "======================================================================"
Write-Host "  AUDION VS ENGINE - ALL-PRESETS SMOKE BENCH"
Write-Host "======================================================================"
Write-Host "Source : $InputFile"
Write-Host "Frames : $Frames"
Write-Host "CUDA   : $Cuda"
Write-Host "Presets: $($presets.Count) discovered"
Write-Host ""

# ---------- Sane env defaults so presets don't trip on missing AUDION_VS_* ----------
#
# Each preset reads only what it needs; superfluous keys are harmless.
#
# IMPORTANT contract note:
#   - AUDION_VS_STRENGTH must NOT be set globally. Precision uses it as a
#     tag ("light"/"medium"/"strong"); Restoration (dehaze, derainbow)
#     parses it as float. A global "medium" therefore makes float() throw
#     for half the suite. Each preset has its own sensible default, so we
#     leave STRENGTH unset and let presets self-default.
$baseEnv = @{
    AUDION_VS_INPUT             = $InputFile
    AUDION_VS_GRAIN_BACK        = '0.6'
    AUDION_VS_SHADOW_THRESHOLD  = '0.20'
    AUDION_VS_TRANSITION        = '0.10'
    AUDION_VS_PREVIEW_MASK      = '0'
    AUDION_VS_DEBAND_RANGE      = '14'
    AUDION_VS_GRAIN_SHADOW      = '1.5'
    AUDION_VS_GRAIN_MID         = '0.9'
    AUDION_VS_GRAIN_HIGH        = '0.4'
    AUDION_VS_HIGH_THRESHOLD    = '0.65'
    AUDION_VS_SIGMA             = '2.5'
    # Restoration legacy
    AUDION_VS_FIELD_ORDER       = 'tff'
    AUDION_VS_QTGMC_PRESET      = 'Faster'
    AUDION_VS_OUTPUT_FPS        = 'single'
    AUDION_VS_RADIUS            = '2'
    AUDION_VS_THSAD             = '200'
    AUDION_VS_BLKSIZE           = '16'
    AUDION_VS_QUANT1            = '24'
    AUDION_VS_QUANT2            = '26'
}

# Per-preset env overrides, keyed by preset basename. Applied on top of
# $baseEnv. Empty string value clears the inherited base entry.
$presetOverrides = @{
    'dehaze_local_contrast'  = @{ AUDION_VS_STRENGTH = '1.0' }
    'derainbow_decross'      = @{ AUDION_VS_STRENGTH = '0.6' }
    'deblock_h264_artefacts' = @{ AUDION_VS_QUANT1 = '24'; AUDION_VS_QUANT2 = '26' }
}

function Invoke-PresetSmoke {
    param(
        [string]$Palette, [string]$Name, [string]$VPY,
        [string]$UseCuda
    )
    # Wipe stale per-preset keys from previous iteration so overrides from a
    # prior preset do not leak forward.
    foreach ($k in @('AUDION_VS_STRENGTH')) {
        Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue
    }
    foreach ($k in $baseEnv.Keys) { Set-Item -Path "Env:$k" -Value $baseEnv[$k] }
    if ($presetOverrides.ContainsKey($Name)) {
        foreach ($k in $presetOverrides[$Name].Keys) {
            $val = $presetOverrides[$Name][$k]
            if ($val -eq '') {
                Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue
            } else {
                Set-Item -Path "Env:$k" -Value $val
            }
        }
    }
    Set-Item -Path 'Env:AUDION_VS_USE_CUDA' -Value $UseCuda

    $modeTag = if ($UseCuda -eq '1') { 'CUDA' } else { 'CPU ' }

    $endIdx  = [Math]::Max(0, $Frames - 1)
    $label   = "{0,-12} {1,-26}" -f $Palette, $Name
    Write-Host ("  [{0}] {1} ... " -f $modeTag, $label) -NoNewline

    # Capture vspipe stderr (plugin / import errors) and ffmpeg stderr into
    # SEPARATE temp logs -- writing both ends of a cmd.exe pipe to the same
    # file triggers ERROR_SHARING_VIOLATION on Windows (the second redirect
    # opens for write while the first still holds the handle), aborts the
    # whole pipeline before any frame is rendered, and leaves the bench
    # falsely reporting "0 PASS / N FAIL" with no diagnostics.
    $errVS = [IO.Path]::GetTempFileName()
    $errFF = [IO.Path]::GetTempFileName()
    try {
        $cmdLine = '"' + $VSPipe + '" -c y4m --end ' + $endIdx + ' "' + $VPY + '" - 2>"' + $errVS + '" | "' + $FFmpeg + '" -hide_banner -loglevel error -y -i - -f null - 2>"' + $errFF + '"'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & cmd.exe /c $cmdLine | Out-Null
        $rc = $LASTEXITCODE
        $sw.Stop()
        $secs = [math]::Round($sw.Elapsed.TotalSeconds, 2)

        $tail = ''
        if ($rc -ne 0) {
            $combined = @()
            $combined += @(Get-Content -LiteralPath $errVS -ErrorAction SilentlyContinue)
            $combined += @(Get-Content -LiteralPath $errFF -ErrorAction SilentlyContinue)
            $lines = $combined | Where-Object { $_ -and $_.Trim() -ne '' }
            if ($lines.Count -gt 0) { $tail = ($lines[-1].Trim()) }
        }

        if ($rc -eq 0) {
            Write-Host ("OK   {0,7} s" -f $secs)
        } else {
            $shortTail = if ($tail.Length -gt 90) { $tail.Substring(0, 90) + '...' } else { $tail }
            Write-Host ("FAIL {0,7} s   {1}" -f $secs, $shortTail)
        }

        return [pscustomobject]@{
            Palette  = $Palette
            Preset   = $Name
            Mode     = $modeTag.Trim()
            Seconds  = $secs
            ExitCode = $rc
            Error    = $tail
        }
    } finally {
        Remove-Item -LiteralPath $errVS -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFF -ErrorAction SilentlyContinue
    }
}

# Build UseCuda mode list per preset
function Get-RunMatrix($preset) {
    $cudaModes = switch ($Cuda) {
        'off'   { ,'0' }
        'on'    { ,'1' }
        'sweep' { if ($preset.Palette -eq 'precision') { @('0','1') } else { ,'0' } }
    }
    $rows = @()
    foreach ($c in $cudaModes) {
        $rows += [pscustomobject]@{ UseCuda=$c }
    }
    return $rows
}

$results = @()
$lastPal = ''
foreach ($p in $presets) {
    if ($p.Palette -ne $lastPal) {
        Write-Host ("-- {0} ---------------------------------------------------" -f $p.Palette)
        $lastPal = $p.Palette
    }
    $matrix = Get-RunMatrix $p
    foreach ($row in $matrix) {
        $results += Invoke-PresetSmoke -Palette $p.Palette -Name $p.Name -VPY $p.Path `
                        -UseCuda $row.UseCuda
    }
}

# ---------- Summary ----------
$total = $results.Count
$pass  = ($results | Where-Object { $_.ExitCode -eq 0 }).Count
$fail  = $total - $pass

Write-Host ""
Write-Host "======================================================================"
Write-Host "  Summary"
Write-Host "======================================================================"
Write-Host ("  Total : {0}   PASS : {1}   FAIL : {2}" -f $total, $pass, $fail)
if ($fail -gt 0) {
    Write-Host ""
    Write-Host "  Failures:"
    $results | Where-Object { $_.ExitCode -ne 0 } | ForEach-Object {
        $shortErr = $_.Error
        if ($shortErr.Length -gt 110) { $shortErr = $shortErr.Substring(0, 110) + '...' }
        Write-Host ("    {0,-12} {1,-26} [{2}] {3}" -f $_.Palette, $_.Preset, $_.Mode, $shortErr)
    }
}

# CUDA delta panel (only meaningful when -Cuda sweep)
if ($Cuda -eq 'sweep') {
    Write-Host ""
    Write-Host "  CUDA vs CPU (Precision):"
    $byPreset = $results | Where-Object { $_.Palette -eq 'precision' } | Group-Object Preset
    # Local row vars MUST NOT be named $cuda -- PowerShell variables are
    # case-insensitive and would clobber the script param $Cuda
    # (ValidateSet('off','on','sweep')) on assignment, breaking later use.
    foreach ($g in $byPreset) {
        $cpuRow  = $g.Group | Where-Object { $_.Mode -eq 'CPU' }
        $cudaRow = $g.Group | Where-Object { $_.Mode -eq 'CUDA' }
        if ($cpuRow -and $cudaRow -and $cpuRow.ExitCode -eq 0 -and $cudaRow.ExitCode -eq 0 -and $cpuRow.Seconds -gt 0) {
            $pct = [math]::Round((($cudaRow.Seconds - $cpuRow.Seconds) / $cpuRow.Seconds) * 100, 1)
            $sign = if ($pct -lt 0) { '' } else { '+' }
            Write-Host ("    {0,-26} CPU={1,7} s  CUDA={2,7} s  delta={3}{4} %" -f $g.Name, $cpuRow.Seconds, $cudaRow.Seconds, $sign, $pct)
        } else {
            Write-Host ("    {0,-26} (incomplete)" -f $g.Name)
        }
    }
}

# JSON report
if ($ReportJson) {
    $payload = [pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        input     = $InputFile
        frames    = $Frames
        cuda_mode = $Cuda
        total     = $total
        pass      = $pass
        fail      = $fail
        results   = $results
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportJson -Encoding UTF8
    Write-Host ""
    Write-Host "  JSON report: $ReportJson"
}

Write-Host ""
if ($fail -gt 0) { exit 1 } else { exit 0 }
