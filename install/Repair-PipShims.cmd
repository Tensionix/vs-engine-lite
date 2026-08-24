@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Repair pip shim shebangs

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "PS1_FILE=%SCRIPT_DIR%\Repair-PipShims.ps1"
set "PS_EXE="

rem Resolve PowerShell: portable -> system pwsh -> Windows PS
if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if not defined PS_EXE goto ERR_NOPS
if not exist "%PS1_FILE%" goto ERR_NOPS1

set "VSDIR=%ROOT%\system_core\vapoursynth"
set "SCRIPTSDIR=%VSDIR%\Scripts"
set "PYEXE=%VSDIR%\python.exe"

set "NO_PAUSE="
set "OPT_WHATIF="
:PARSE
if "%~1"=="" goto SHOW
if /I "%~1"=="/WHATIF"  ( set "OPT_WHATIF=-WhatIfOnly" & shift & goto PARSE )
if /I "%~1"=="/N"       ( set "OPT_WHATIF=-WhatIfOnly" & shift & goto PARSE )
if /I "%~1"=="/NOPAUSE" ( set "NO_PAUSE=1" & shift & goto PARSE )
shift
goto PARSE

:SHOW
echo ======================================================================
echo   AUDION VS ENGINE - REPAIR PIP SHIM SHEBANGS
echo ======================================================================
echo PS engine:  %PS_EXE%
echo PS1 file:   %PS1_FILE%
echo ScriptsDir: %SCRIPTSDIR%
echo PyExe:      %PYEXE%
if defined OPT_WHATIF echo Mode:       %OPT_WHATIF%
if defined NO_PAUSE echo Noninteractive: ON
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ScriptsDir "%SCRIPTSDIR%" -PyExe "%PYEXE%" %OPT_WHATIF%
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto ERR_RUN
echo [DONE] Shim repair completed.
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
echo [ERROR] Shim repair failed (exit %RC%).
if not defined NO_PAUSE pause
exit /b %RC%
