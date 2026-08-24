[CmdletBinding()]
param(
    [ValidateSet('None', 'BtbN', 'Gyan')]
    [string]$FFmpegSource = 'None'
)

$ErrorActionPreference = "Stop"

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $installDir

# Portable 7-Zip bootstrap + universal extractor. Build steps [01]/[02]
# install 7zr.exe and 7za.exe together with Python so later installers do not
# depend on hidden lazy setup.
. (Join-Path $installDir 'Ensure-7zip.ps1')

$downloadDir = Join-Path $installDir "download"
$runtimeDir = Join-Path $rootDir "runtime"
$wheelhouseDir = Join-Path $rootDir "wheelhouse"
$requirementsFile = Join-Path $installDir "requirements_full.in"
$guiSmokeScript = Join-Path $rootDir "system_core\ui_nicegui\app.py"

$pythonMinor = 12
$headers = @{ 'User-Agent' = 'Audion-Python-Portable-Template' }

$pyPatch = -1
for ($i = 0; $i -le 40; $i++) {
    $uri = "https://www.python.org/ftp/python/3.$pythonMinor.$i/python-3.$pythonMinor.$i-embed-amd64.zip"
    try {
        Invoke-WebRequest -Headers $headers -Uri $uri -Method Head -TimeoutSec 10 | Out-Null
        $pyPatch = $i
    } catch {
        if ($pyPatch -ge 0) { break }
    }
}
if ($pyPatch -lt 0) { throw "Could not resolve any Python 3.$pythonMinor.x embed-amd64 build" }
$pythonVersion = "3.$pythonMinor.$pyPatch"
$pythonZipName = "python-$pythonVersion-embed-amd64.zip"
$pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/$pythonZipName"
$pythonZipPath = Join-Path $downloadDir $pythonZipName
$getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
$getPipPath = Join-Path $downloadDir "get-pip.py"

Write-Host "======================================================================"
Write-Host "AUDION PYTHON PORTABLE TEMPLATE - BUILD PORTABLE ENV (PS)"
Write-Host "======================================================================"
Write-Host "Root:        $rootDir"
Write-Host "Install:     $installDir"
Write-Host "Download:    $downloadDir"
Write-Host "Runtime:     $runtimeDir"
Write-Host "Wheelhouse:  $wheelhouseDir"
Write-Host ""

New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $wheelhouseDir | Out-Null

Write-Host "[1/8] Ensuring portable 7-Zip..."
$bin7zr = Ensure-7zr -ProjectRoot $rootDir
$bin7za = Ensure-7za -ProjectRoot $rootDir
Write-Host "      [OK] 7zr: $bin7zr"
Write-Host "      [OK] 7za: $bin7za"

Write-Host "[2/8] Downloading Python Embedded..."
Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZipPath

Write-Host "[3/8] Extracting runtime..."
if (Test-Path $runtimeDir) {
    Get-ChildItem -Force $runtimeDir | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
Expand-7zArchive -Archive $pythonZipPath -Destination $runtimeDir -ProjectRoot $rootDir

Write-Host "[4/8] Enabling import site..."
$pthFile = Join-Path $runtimeDir "python3$pythonMinor._pth"
if (-not (Test-Path $pthFile)) {
    throw "Missing file: $pthFile"
}
$pthLines = Get-Content $pthFile
$patched = New-Object System.Collections.Generic.List[string]
$hasProjectRoot = $pthLines -contains ".."
foreach ($line in $pthLines) {
    if ($line -eq "#import site") {
        $patched.Add("import site")
    } else {
        $patched.Add($line)
    }
    if (-not $hasProjectRoot -and $line -eq ".") {
        $patched.Add("..")
        $hasProjectRoot = $true
    }
}
$patched | Set-Content $pthFile -Encoding ASCII

Write-Host "[5/8] Downloading get-pip.py..."
# A dropped connection here used to kill the whole project build.
$getPipOk = $false
foreach ($getPipTry in 1..5) {
    $getPipTmp = "$($getPipPath).part"
    try {
        Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipTmp -TimeoutSec 120 -UseBasicParsing
        $getPipSize = (Get-Item -LiteralPath $getPipTmp).Length
        if ($getPipSize -lt 1000000) { throw "truncated body: $getPipSize bytes" }
        Move-Item -LiteralPath $getPipTmp -Destination $getPipPath -Force
        $getPipOk = $true
        break
    } catch {
        Write-Host "  get-pip.py attempt $getPipTry failed: $($_.Exception.Message)"
        Remove-Item -LiteralPath $getPipTmp -Force -ErrorAction SilentlyContinue
        if ($getPipTry -lt 5) { Start-Sleep -Seconds (3 * $getPipTry) }
    }
}
if (-not $getPipOk) { throw "Could not download get-pip.py after 5 attempts - the network dropped every time." }
$pythonExe = Join-Path $runtimeDir "python.exe"
if (-not (Test-Path $pythonExe)) {
    throw "Missing file: $pythonExe"
}

Write-Host "[6/8] Installing pip..."
& $pythonExe $getPipPath
if ($LASTEXITCODE -ne 0) { throw "pip bootstrap failed (exit $LASTEXITCODE)" }

Write-Host "[7/8] Building wheelhouse and installing packages..."
Get-ChildItem -Force $wheelhouseDir |
    Where-Object { $_.Name -ne ".gitkeep" } |
    Remove-Item -Force -Recurse
& $pythonExe -m pip install --disable-pip-version-check --upgrade setuptools wheel packaging
if ($LASTEXITCODE -ne 0) { throw "packaging bootstrap failed (exit $LASTEXITCODE)" }
& $pythonExe -m pip wheel --disable-pip-version-check --prefer-binary --no-build-isolation --timeout 120 --retries 12 -r $requirementsFile -w $wheelhouseDir
if ($LASTEXITCODE -ne 0) { throw "wheelhouse build failed (exit $LASTEXITCODE)" }
& $pythonExe -m pip install --disable-pip-version-check --no-index --find-links=$wheelhouseDir -r $requirementsFile
if ($LASTEXITCODE -ne 0) { throw "package install from wheelhouse failed (exit $LASTEXITCODE)" }

Write-Host "[8/8] Verifying orchestrator + GUI runtime..."
& $pythonExe -c "import yaml, nicegui, webview, psutil, rich; print('OK orchestrator GUI deps')"
if ($LASTEXITCODE -ne 0) { throw "GUI/orchestrator dependency import check failed (exit $LASTEXITCODE)" }
if (Test-Path $guiSmokeScript) {
    & $pythonExe $guiSmokeScript --smoke
    if ($LASTEXITCODE -ne 0) { throw "NiceGUI app smoke failed (exit $LASTEXITCODE)" }
}


Write-Host ""
Write-Host "[SUCCESS] Portable environment is ready."
Write-Host "[INFO] Full stack Doctor is step [04], after VapourSynth/FFmpeg install."
Write-Host "[INFO] Release licensing is generated later from the finalized release contents."

if ($FFmpegSource -ne 'None') {
    $ffmpegScriptName = if ($FFmpegSource -eq 'Gyan') {
        'Install-Portable-FFmpeg-Gyan.cmd'
    } else {
        'Install-Portable-FFmpeg-BtbN.cmd'
    }
    $ffmpegInstaller = Join-Path $installDir $ffmpegScriptName
    Write-Host "[OPTIONAL] Installing FFmpeg provider: $FFmpegSource"
    & $env:ComSpec /d /c "call `"$ffmpegInstaller`" /NOPAUSE"
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg $FFmpegSource installer failed (exit $LASTEXITCODE)" }
}
