@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - All-Presets Smoke Bench

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "PS1_FILE=%SCRIPT_DIR%\Bench-AllPresets.ps1"
set "PS_EXE="

rem Resolve PowerShell: portable -> system pwsh -> Windows PS
if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if not defined PS_EXE goto ERR_NOPS
if not exist "%PS1_FILE%" goto ERR_NOPS1

if "%~1"=="" goto ASK_INPUT
set "INPUT_FILE=%~1"
goto HAVE_INPUT

:ASK_INPUT
echo.
set /p "INPUT_FILE=Drag and drop a video file here (or paste the path) and press Enter: "
set "INPUT_FILE=%INPUT_FILE:"=%"
if not defined INPUT_FILE goto ERR_NOINPUT

:HAVE_INPUT
if not exist "%INPUT_FILE%" (
    echo [ERROR] File not found: %INPUT_FILE%
    if not defined AUDION_NO_PAUSE pause
    exit /b 1
)

rem Optional second arg = frame count (default 30); third = cuda mode (off/on/sweep)
set "FRAMES=%~2"
if not defined FRAMES set "FRAMES=30"
set "CUDA_MODE=%~3"
if not defined CUDA_MODE set "CUDA_MODE=off"

rem Auto-stamped JSON report next to logs/
set "TS="
for /f "usebackq delims=" %%t in (`"%PS_EXE%" -NoLogo -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%t"
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs" >nul 2>nul
set "REPORT=%ROOT%\logs\bench_all_presets_%TS%.json"

echo.
echo ======================================================================
echo   AUDION VS ENGINE - ALL-PRESETS SMOKE BENCH (CMD wrapper)
echo ======================================================================
echo PS engine: %PS_EXE%
echo PS1 file:  %PS1_FILE%
echo Project:   %ROOT%
echo Source:    %INPUT_FILE%
echo Frames:    %FRAMES%
echo CUDA mode: %CUDA_MODE%   (off / on / sweep)
echo Report:    %REPORT%
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ProjectRoot "%ROOT%" -InputFile "%INPUT_FILE%" -Frames %FRAMES% -Cuda %CUDA_MODE% -ReportJson "%REPORT%"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto ERR_RUN
echo [DONE] All presets passed.
if not defined AUDION_NO_PAUSE pause
exit /b 0

:ERR_NOPS
echo [ERROR] No PowerShell found (portable, system pwsh, or powershell.exe).
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_NOPS1
echo [ERROR] PS1 not found: %PS1_FILE%
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_NOINPUT
echo [ERROR] No input file given. Drag a video onto this .cmd or pass the path as the first argument.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_RUN
echo [ERROR] Some presets failed (exit %RC%). See report: %REPORT%
if not defined AUDION_NO_PAUSE pause
exit /b %RC%
