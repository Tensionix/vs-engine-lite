@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

for %%A in ("%SCRIPT_DIR%") do set "HERE=%%~nxA"

set "ROOT=%SCRIPT_DIR%"
if /I "%HERE%"=="install" for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

rem Runtime/generated folders are kept as empty release placeholders.
call :MK "%ROOT%\input"
call :MK "%ROOT%\output"
call :MK_KEEP "%ROOT%\logs"
call :MK_KEEP "%ROOT%\report"
call :MK_KEEP "%ROOT%\release"
call :MK_KEEP "%ROOT%\data"
call :MK_KEEP "%ROOT%\runtime"
call :MK_KEEP "%ROOT%\wheelhouse"
call :MK "%ROOT%\._runtime"

rem Config folders are part of the lightweight source release.
call :MK "%ROOT%\config"
call :MK_KEEP "%ROOT%\config\profiles"

rem Installer cache placeholder.
call :MK "%ROOT%\install"
call :MK_KEEP "%ROOT%\install\download"

rem Source/runtime target placeholders. Install scripts populate these later.
call :MK "%ROOT%\system_core"
call :MK "%ROOT%\Tools"
call :MK_KEEP "%ROOT%\Tools\ffmpeg"
call :MK_KEEP "%ROOT%\Tools\ffmpeg\bin"
call :MK_KEEP "%ROOT%\system_core\vapoursynth"
call :MK_KEEP "%ROOT%\system_core\powershell"
call :MK_KEEP "%ROOT%\system_core\7zip"

rem License output placeholders. Policy docs live next to these.
call :MK_KEEP "%ROOT%\licenses"
call :MK "%ROOT%\system_core\license"
call :MK_KEEP "%ROOT%\system_core\license\files"
call :MK_KEEP "%ROOT%\system_core\license\fallbacks"

exit /b 0

:MK
if not exist "%~1\" mkdir "%~1" >nul 2>nul
goto :eof

:MK_KEEP
call :MK "%~1"
goto :eof
