@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Install Portable VapourSynth

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "NO_PAUSE="
for %%A in (%*) do if /I "%%~A"=="/NOPAUSE" set "NO_PAUSE=1"

set "PS1_FILE=%SCRIPT_DIR%\Install-Portable-VapourSynth.ps1"
set "PS_EXE="

rem Resolve PowerShell: portable -> system pwsh -> Windows PS
if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if not defined PS_EXE goto ERR_NOPS
if not exist "%PS1_FILE%" goto ERR_NOPS1

rem Parse simple flags into separate vars (avoid variable-quoting hell)
set "OPT_FORCE="
set "OPT_VSVER="
:PARSE
if "%~1"=="" goto SHOW
if /I "%~1"=="/F"     ( set "OPT_FORCE=-Force" & shift & goto PARSE )
if /I "%~1"=="/FORCE" ( set "OPT_FORCE=-Force" & shift & goto PARSE )
if /I "%~1"=="/R"     ( set "OPT_VSVER=-VSVersion %~2" & shift & shift & goto PARSE )
if /I "%~1"=="/NOPAUSE" ( set "NO_PAUSE=1" & shift & goto PARSE )
shift
goto PARSE

:SHOW
echo ======================================================================
echo   AUDION VS ENGINE - INSTALL PORTABLE VAPOURSYNTH (CMD wrapper)
echo ======================================================================
echo PS engine: %PS_EXE%
echo PS1 file:  %PS1_FILE%
echo Project:   %ROOT%
if defined OPT_FORCE echo Mode:      %OPT_FORCE%
if defined OPT_VSVER echo Version:   %OPT_VSVER%
if defined NO_PAUSE  echo Noninteractive: ON
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ProjectRoot "%ROOT%" %OPT_FORCE% %OPT_VSVER%
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto ERR_RUN
echo [DONE] VapourSynth portable install completed.
if not defined NO_PAUSE pause
exit /b 0

:ERR_NOPS
echo [ERROR] No PowerShell found (portable, system pwsh, or powershell.exe).
if not defined NO_PAUSE pause
exit /b 1

:ERR_NOPS1
echo [ERROR] PS1 not found: %PS1_FILE%
if not defined NO_PAUSE pause
exit /b 1

:ERR_RUN
echo [ERROR] VapourSynth install failed (exit %RC%).
if not defined NO_PAUSE pause
exit /b %RC%
