@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion Python Portable Template - Build Portable Env

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "INSTALL_DIR=%ROOT%\install"
set "DOWNLOAD_DIR=%INSTALL_DIR%\download"
set "RUNTIME_DIR=%ROOT%\runtime"
set "WHEELHOUSE_DIR=%ROOT%\wheelhouse"
set "REQ_FILE=%INSTALL_DIR%\requirements_full.in"
set "GUI_SMOKE=%ROOT%\system_core\ui_nicegui\app.py"
set "GET_PIP=%DOWNLOAD_DIR%\get-pip.py"

echo [preflight] Checking and repairing CMD encoding...
call "%INSTALL_DIR%\Check-CmdEncoding.cmd" -Fix
if errorlevel 1 goto ERR_CMD_ENCODING

set "PYTHON_MINOR=12"
for /f "usebackq delims=" %%V in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $latest=$null; for($i=0; $i -le 40; $i++){ $v='3.%PYTHON_MINOR%.'+$i; $u='https://www.python.org/ftp/python/'+$v+'/python-'+$v+'-embed-amd64.zip'; try{ Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 10 | Out-Null; $latest=$v } catch { if($latest){ break } } }; if(-not $latest){ exit 1 }; $latest"`) do set "PYTHON_VERSION=%%V"
if not defined PYTHON_VERSION goto USE_POWERSHELL
set "PYTHON_ZIP=python-%PYTHON_VERSION%-embed-amd64.zip"
set "PYTHON_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/%PYTHON_ZIP%"
set "PYTHON_ZIP_PATH=%DOWNLOAD_DIR%\%PYTHON_ZIP%"

call "%INSTALL_DIR%\init_folders.cmd"

echo ======================================================================
echo   AUDION PYTHON PORTABLE TEMPLATE - BUILD PORTABLE ENV
echo ======================================================================
echo Root:       %ROOT%
echo Install:    %INSTALL_DIR%
echo Download:   %DOWNLOAD_DIR%
echo Runtime:    %RUNTIME_DIR%
echo Wheelhouse: %WHEELHOUSE_DIR%
echo.

if not exist "%REQ_FILE%" goto ERR_REQ

echo [1/8] Ensuring portable 7-Zip...
call :ENSURE_7ZIP
if errorlevel 1 goto ERR_7ZIP

where curl.exe >nul 2>nul
if errorlevel 1 goto USE_POWERSHELL

where tar.exe >nul 2>nul
if errorlevel 1 goto USE_POWERSHELL

echo [2/8] Downloading Python Embedded...
curl.exe -L --fail --retry 5 --connect-timeout 30 -o "%PYTHON_ZIP_PATH%" "%PYTHON_URL%"
if errorlevel 1 goto ERR_DOWNLOAD

echo [3/8] Extracting runtime...
if exist "%RUNTIME_DIR%\" rd /s /q "%RUNTIME_DIR%" >nul 2>nul
mkdir "%RUNTIME_DIR%" >nul 2>nul
tar.exe -xf "%PYTHON_ZIP_PATH%" -C "%RUNTIME_DIR%"
if errorlevel 1 goto USE_POWERSHELL

echo [4/8] Enabling import site...
call :PATCH_PTH "%RUNTIME_DIR%\python3%PYTHON_MINOR%._pth"
if errorlevel 1 goto ERR_PTH

echo [5/8] Downloading get-pip.py...
curl.exe -L --fail --retry 5 --connect-timeout 30 -o "%GET_PIP%" "https://bootstrap.pypa.io/get-pip.py"
if errorlevel 1 goto ERR_GETPIP

if not exist "%RUNTIME_DIR%\python.exe" goto ERR_PYTHON

echo [6/8] Installing pip...
"%RUNTIME_DIR%\python.exe" "%GET_PIP%"
if errorlevel 1 goto ERR_PIP

echo [7/8] Building wheelhouse...
for /f "delims=" %%F in ('dir /a /b "%WHEELHOUSE_DIR%" 2^>nul') do (
  if /I not "%%F"==".gitkeep" (
    if exist "%WHEELHOUSE_DIR%\%%F\" (
      rd /s /q "%WHEELHOUSE_DIR%\%%F"
    ) else (
      del /f /q "%WHEELHOUSE_DIR%\%%F"
    )
  )
)
"%RUNTIME_DIR%\python.exe" -m pip install --disable-pip-version-check --upgrade setuptools wheel packaging
if errorlevel 1 goto ERR_BOOTSTRAP
"%RUNTIME_DIR%\python.exe" -m pip wheel --disable-pip-version-check --prefer-binary --no-build-isolation --timeout 120 --retries 12 -r "%REQ_FILE%" -w "%WHEELHOUSE_DIR%"
if errorlevel 1 goto ERR_WHEELS

echo [7/8] Installing packages from local wheelhouse...
"%RUNTIME_DIR%\python.exe" -m pip install --disable-pip-version-check --no-index --find-links="%WHEELHOUSE_DIR%" -r "%REQ_FILE%"
if errorlevel 1 goto ERR_INSTALL

echo [8/8] Verifying orchestrator + GUI runtime...
"%RUNTIME_DIR%\python.exe" -c "import yaml, nicegui, webview, psutil, rich; print('OK orchestrator GUI deps')"
if errorlevel 1 goto ERR_VERIFY
if exist "%GUI_SMOKE%" (
  "%RUNTIME_DIR%\python.exe" "%GUI_SMOKE%" --smoke
  if errorlevel 1 goto ERR_VERIFY
)

echo.
echo [SUCCESS] Portable environment is ready.
echo [INFO] Full stack Doctor is step [04], after VapourSynth/FFmpeg install.
echo [INFO] Release licensing is generated later from the finalized release contents.
if not defined AUDION_NO_PAUSE pause
exit /b 0

:USE_POWERSHELL
echo [INFO] CMD prerequisites are incomplete.
echo [INFO] Falling back to Build_Portable_Env.ps1
call "%INSTALL_DIR%\Build_Portable_Env.cmd"
exit /b %errorlevel%

:ENSURE_7ZIP
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; . '%INSTALL_DIR%\Ensure-7zip.ps1'; $r=Ensure-7zr -ProjectRoot '%ROOT%'; $a=Ensure-7za -ProjectRoot '%ROOT%'; Write-Host ('      [OK] 7zr: '+$r); Write-Host ('      [OK] 7za: '+$a)"
exit /b %errorlevel%

:PATCH_PTH
set "PTH_FILE=%~1"
if not exist "%PTH_FILE%" exit /b 1
set "TMP_FILE=%PTH_FILE%.tmp"
set "HAS_PROJECT_ROOT=0"
for /f "usebackq delims=" %%L in ("%PTH_FILE%") do (
  if "%%L"==".." set "HAS_PROJECT_ROOT=1"
)
break > "%TMP_FILE%"
for /f "usebackq delims=" %%L in ("%PTH_FILE%") do (
  set "LINE=%%L"
  if "!LINE!"=="#import site" (
    >>"%TMP_FILE%" echo import site
  ) else (
    >>"%TMP_FILE%" echo %%L
  )
  if "!LINE!"=="." if "!HAS_PROJECT_ROOT!"=="0" (
    >>"%TMP_FILE%" echo ..
    set "HAS_PROJECT_ROOT=1"
  )
)
move /y "%TMP_FILE%" "%PTH_FILE%" >nul
exit /b 0

:ERR_REQ
echo [ERROR] requirements_full.in was not found.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_CMD_ENCODING
echo [ERROR] CMD encoding check/fix failed.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_7ZIP
echo [ERROR] Failed to install portable 7-Zip into system_core\7zip.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_DOWNLOAD
echo [ERROR] Failed to download Python Embedded ZIP.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_PTH
echo [ERROR] Failed to patch python3%PYTHON_MINOR%._pth
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_GETPIP
echo [ERROR] Failed to download get-pip.py
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_PYTHON
echo [ERROR] runtime\python.exe was not found after extraction.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_PIP
echo [ERROR] Failed to install pip into portable runtime.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_BOOTSTRAP
echo [ERROR] Failed to install packaging bootstrap into portable runtime.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_WHEELS
echo [ERROR] Failed to build wheelhouse.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_INSTALL
echo [ERROR] Failed to install packages from wheelhouse.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_VERIFY
echo [ERROR] Orchestrator / GUI runtime verification failed.
if not defined AUDION_NO_PAUSE pause
exit /b 1

