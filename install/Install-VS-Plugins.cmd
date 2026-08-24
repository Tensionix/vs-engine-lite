@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Install VS Plugins

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "NO_PAUSE="
for %%A in (%*) do if /I "%%~A"=="/NOPAUSE" set "NO_PAUSE=1"

set "PS1_FILE=%SCRIPT_DIR%\Install-VS-Plugins.ps1"
set "PS_EXE="

if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if not defined PS_EXE goto ERR_NOPS
if not exist "%PS1_FILE%" goto ERR_NOPS1

rem Default: install all plugins INCLUDING bm3dcuda. The DLL load on a non-NVIDIA
rem machine fails silently inside VS and presets fall back via hasattr-check.
rem Pass /NO-CUDA (or legacy /CUDA is accepted but does nothing - it is the
rem default now) to skip the bm3dcuda plugin entirely.
rem   /NOPAUSE         - non-interactive mode for GUI / automation callers
set "OPT_NO_CUDA="
:PARSE
if "%~1"=="" goto SHOW
if /I "%~1"=="/NO-CUDA" ( set "OPT_NO_CUDA=-NoCUDA" & shift & goto PARSE )
if /I "%~1"=="/NOCUDA"  ( set "OPT_NO_CUDA=-NoCUDA" & shift & goto PARSE )
if /I "%~1"=="/CUDA"     ( shift & goto PARSE )
if /I "%~1"=="/WITHCUDA" ( shift & goto PARSE )
if /I "%~1"=="/NOPAUSE"  ( set "NO_PAUSE=1" & shift & goto PARSE )
shift
goto PARSE

:SHOW
echo ======================================================================
echo   AUDION VS ENGINE - INSTALL VS PLUGINS (CMD wrapper)
echo ======================================================================
echo PS engine: %PS_EXE%
echo Project:   %ROOT%
if not defined OPT_NO_CUDA echo CUDA path: ON  (bm3dcuda included; harmless on non-NVIDIA)
if defined OPT_NO_CUDA     echo CUDA path: OFF (opt-out via /NO-CUDA)
if defined NO_PAUSE        echo Noninteractive: ON
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ProjectRoot "%ROOT%" %OPT_NO_CUDA%
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [DONE] All plugins installed.
  if not defined NO_PAUSE pause
  exit /b 0
)
if "%RC%"=="2" (
  echo [PARTIAL] Some plugins failed - see summary above.
  if not defined NO_PAUSE pause
  exit /b 2
)
echo [ERROR] Plugin install failed (exit %RC%).
if not defined NO_PAUSE pause
exit /b %RC%

:ERR_NOPS
echo [ERROR] No PowerShell found.
if not defined NO_PAUSE pause
exit /b 1

:ERR_NOPS1
echo [ERROR] PS1 not found: %PS1_FILE%
if not defined NO_PAUSE pause
exit /b 1
