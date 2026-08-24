@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - CUDA bench (pure pipeline, no encode)

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "PS1_FILE=%SCRIPT_DIR%\Bench-CUDA.ps1"
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
rem Strip surrounding quotes if user dragged a path with spaces
set "INPUT_FILE=%INPUT_FILE:"=%"
if not defined INPUT_FILE goto ERR_NOINPUT

:HAVE_INPUT
if not exist "%INPUT_FILE%" (
    echo [ERROR] File not found: %INPUT_FILE%
    if not defined AUDION_NO_PAUSE pause
    exit /b 1
)

set "OPT_SIGMA="
if not "%~2"=="" set "OPT_SIGMA=-Sigma %~2"

echo.
echo ======================================================================
echo   AUDION VS ENGINE - CUDA BENCH (CMD wrapper)
echo ======================================================================
echo PS engine: %PS_EXE%
echo PS1 file:  %PS1_FILE%
echo Project:   %ROOT%
echo Source:    %INPUT_FILE%
echo.
echo Open Task Manager - Performance - GPU now, or run 'nvidia-smi -l 1' in
echo another terminal, to watch the CUDA pass load the card.
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ProjectRoot "%ROOT%" -InputFile "%INPUT_FILE%" %OPT_SIGMA%
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto ERR_RUN
echo [DONE] Bench finished.
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
echo [ERROR] Bench failed (exit %RC%).
if not defined AUDION_NO_PAUSE pause
exit /b %RC%
