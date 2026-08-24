@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine Lite - Install Portable FFmpeg BtbN Release

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "PS1_FILE=%SCRIPT_DIR%\Install-Portable-FFmpeg-BtbN.ps1"
set "GYAN_CMD=%SCRIPT_DIR%\Install-Portable-FFmpeg-Gyan.cmd"
set "PS_EXE="
set "NO_PAUSE=0"
if /I "%AUDION_NO_PAUSE%"=="1" set "NO_PAUSE=1"
set "OPT_FORCE="
set "OPT_VARIANT=-Variant gpl"
set "OPT_SOURCE=-Source BtbN"
set "OPT_ROLLING="

:PARSE
if "%~1"=="" goto DONE_ARGS
if /I "%~1"=="/NOPAUSE" set "NO_PAUSE=1" & shift & goto PARSE
if /I "%~1"=="--no-pause" set "NO_PAUSE=1" & shift & goto PARSE
if /I "%~1"=="/F" set "OPT_FORCE=-Force" & shift & goto PARSE
if /I "%~1"=="/FORCE" set "OPT_FORCE=-Force" & shift & goto PARSE
if /I "%~1"=="/V" set "OPT_VARIANT=-Variant %~2" & shift & shift & goto PARSE
if /I "%~1"=="--variant" set "OPT_VARIANT=-Variant %~2" & shift & shift & goto PARSE
if /I "%~1"=="/SOURCE" set "OPT_SOURCE=-Source %~2" & shift & shift & goto PARSE
if /I "%~1"=="--source" set "OPT_SOURCE=-Source %~2" & shift & shift & goto PARSE
if /I "%~1"=="/ALLOWROLLING" set "OPT_ROLLING=-AllowRollingBranch" & shift & goto PARSE
if /I "%~1"=="--allow-rolling-branch" set "OPT_ROLLING=-AllowRollingBranch" & shift & goto PARSE
shift
goto PARSE
:DONE_ARGS

if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if not defined PS_EXE goto ERR_NOPS
if not exist "%PS1_FILE%" goto ERR_NOPS1

echo ======================================================================
echo   AUDION VS ENGINE LITE - INSTALL PORTABLE FFMPEG BTBN RELEASE
echo ======================================================================
echo PS engine: %PS_EXE%
echo Project:   %ROOT%
if defined OPT_FORCE echo Mode:      %OPT_FORCE%
echo Variant:   %OPT_VARIANT%
echo Source:    %OPT_SOURCE%
if defined OPT_ROLLING echo Policy:    emergency rolling release branch explicitly allowed
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -ProjectRoot "%ROOT%" %OPT_FORCE% %OPT_VARIANT% %OPT_SOURCE% %OPT_ROLLING%
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="20" goto FALLBACK_GYAN
if not "%RC%"=="0" goto ERR_RUN
echo [DONE] FFmpeg BtbN portable install completed.
call :PAUSE_IF_NEEDED
exit /b 0


:FALLBACK_GYAN
echo [PROVIDER] BtbN has no exact stable-tag binary. Switching to Gyan exact stable.
if not exist "%GYAN_CMD%" goto ERR_NOGYAN
call "%GYAN_CMD%" /NOPAUSE
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto ERR_FALLBACK
echo [DONE] FFmpeg Gyan provider fallback completed.
call :PAUSE_IF_NEEDED
exit /b 0

:ERR_NOGYAN
echo [ERROR] Gyan fallback installer not found: %GYAN_CMD%
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_FALLBACK
echo [ERROR] Gyan provider fallback failed. Exit %RC%.
call :PAUSE_IF_NEEDED
exit /b %RC%

:ERR_NOPS
echo [ERROR] No PowerShell found.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_NOPS1
echo [ERROR] PS1 not found: %PS1_FILE%
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_RUN
echo [ERROR] FFmpeg BtbN install failed. Exit %RC%.
call :PAUSE_IF_NEEDED
exit /b %RC%

:PAUSE_IF_NEEDED
if not "%NO_PAUSE%"=="1" pause
goto :eof
