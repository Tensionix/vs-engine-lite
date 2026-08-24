<#
.SYNOPSIS
  Audion VS Engine - Pure-pipeline CPU vs CUDA bench (no encode in the loop).

.DESCRIPTION
  Runs vspipe -> ffmpeg null muxer for shadow_denoise_sota and filmic_rebuild,
  in both CPU and CUDA modes. By piping into the null muxer instead of libx264,
  the bench isolates the VapourSynth denoise pipeline from CPU encode bottleneck,
  which is what a 12-core libx264 CRF18 run actually saturates.

  Open Task Manager (Performance -> GPU) or `nvidia-smi -l 1` in another window
  while running this to confirm the CUDA pass actually loads the GPU.

.PARAMETER ProjectRoot
  Absolute path to project root.

.PARAMETER Input
  Source file (drag-n-drop).

.PARAMETER Sigma
  BM3D sigma. Default 2.5.
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$InputFile,
    [double]$Sigma = 2.5
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputFile)) { throw "Input not found: $InputFile" }

$VSPipe = Join-Path $ProjectRoot 'system_core\vapoursynth\Scripts\vspipe.exe'
$FFmpeg = Join-Path $ProjectRoot 'Tools\ffmpeg\bin\ffmpeg.exe'
$ShadowVPY = Join-Path $ProjectRoot 'system_core\presets\precision\shadow_denoise_sota.vpy'
$FilmicVPY = Join-Path $ProjectRoot 'system_core\presets\precision\filmic_rebuild.vpy'

foreach ($p in @($VSPipe, $FFmpeg, $ShadowVPY, $FilmicVPY)) {
    if (-not (Test-Path $p)) { throw "Required component missing: $p" }
}

$InputFile = (Resolve-Path $InputFile).Path
Write-Host "======================================================================"
Write-Host "  AUDION VS ENGINE - CUDA BENCH (pure pipeline, no encode)"
Write-Host "======================================================================"
Write-Host "Source : $InputFile"
Write-Host "Sigma  : $Sigma"
Write-Host ""
Write-Host "Tip: open Task Manager -> Performance -> GPU, or run 'nvidia-smi -l 1'"
Write-Host "     in another terminal. Watch the CUDA pass load the GPU."
Write-Host ""

# Common env (preset-agnostic + shared params)
$baseEnv = @{
    AUDION_VS_INPUT             = $InputFile
    AUDION_VS_SIGMA             = "$Sigma"
    AUDION_VS_STRENGTH          = 'medium'
    AUDION_VS_GRAIN_BACK        = '0.6'
    AUDION_VS_SHADOW_THRESHOLD  = '0.20'
    AUDION_VS_TRANSITION        = '0.10'
    AUDION_VS_PREVIEW_MASK      = '0'
    AUDION_VS_DEBAND_RANGE      = '14'
    AUDION_VS_GRAIN_SHADOW      = '1.5'
    AUDION_VS_GRAIN_MID         = '0.9'
    AUDION_VS_GRAIN_HIGH        = '0.4'
    AUDION_VS_HIGH_THRESHOLD    = '0.65'
}

function Invoke-PipelineRun {
    param([string]$Label, [string]$VPY, [string]$UseCuda)

    foreach ($k in $baseEnv.Keys) { Set-Item -Path "Env:$k" -Value $baseEnv[$k] }
    Set-Item -Path 'Env:AUDION_VS_USE_CUDA' -Value $UseCuda

    $modeTag = if ($UseCuda -eq '1') { 'CUDA' } else { 'CPU ' }
    Write-Host ("  [{0}] {1} ... " -f $modeTag, $Label) -NoNewline

    # Build a single command string for cmd.exe so the pipe between vspipe and
    # ffmpeg lives inside a real shell (PowerShell's native pipe between two
    # external processes serializes through the host - much slower).
    $cmdLine = '"' + $VSPipe + '" -c y4m "' + $VPY + '" - 2> nul | "' + $FFmpeg + '" -hide_banner -loglevel error -y -i - -f null -'

    $sw = [Diagnostics.Stopwatch]::StartNew()
    & cmd.exe /c $cmdLine
    $rc = $LASTEXITCODE
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    if ($rc -eq 0) {
        Write-Host ("{0,7} s" -f $secs)
    } else {
        Write-Host ("FAILED (exit {0})" -f $rc)
    }
    return [pscustomobject]@{ Label=$Label; Mode=$modeTag; Seconds=$secs; ExitCode=$rc }
}

$results = @()
$results += Invoke-PipelineRun -Label 'shadow_denoise_sota' -VPY $ShadowVPY -UseCuda '0'
$results += Invoke-PipelineRun -Label 'shadow_denoise_sota' -VPY $ShadowVPY -UseCuda '1'
$results += Invoke-PipelineRun -Label 'filmic_rebuild'      -VPY $FilmicVPY -UseCuda '0'
$results += Invoke-PipelineRun -Label 'filmic_rebuild'      -VPY $FilmicVPY -UseCuda '1'

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "  Results"
Write-Host "----------------------------------------------------------------------"
$pairs = $results | Group-Object Label
foreach ($g in $pairs) {
    $cpu  = $g.Group | Where-Object { $_.Mode.Trim() -eq 'CPU' }
    $cuda = $g.Group | Where-Object { $_.Mode.Trim() -eq 'CUDA' }
    if ($cpu -and $cuda -and $cpu.ExitCode -eq 0 -and $cuda.ExitCode -eq 0 -and $cpu.Seconds -gt 0) {
        $pct = [math]::Round((($cuda.Seconds - $cpu.Seconds) / $cpu.Seconds) * 100, 1)
        $sign = if ($pct -lt 0) { "" } else { "+" }
        Write-Host ("  {0,-22}  CPU={1,7} s   CUDA={2,7} s   Δ={3}{4} %" -f $g.Name, $cpu.Seconds, $cuda.Seconds, $sign, $pct)
    } else {
        Write-Host ("  {0,-22}  (incomplete)" -f $g.Name)
    }
}
Write-Host ""
Write-Host "Note: GPU utilization in Task Manager looks low (~5-10%) even on a"
Write-Host "      working CUDA path -- BM3D is memory-bandwidth bound and runs in"
Write-Host "      bursts. The wall-time delta and 'doctor' live BM3D CUDA invocation"
Write-Host "      are the authoritative signals that CUDA is being used."
Write-Host ""
exit 0
