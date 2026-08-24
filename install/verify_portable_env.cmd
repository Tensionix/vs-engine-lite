@echo off
setlocal EnableExtensions

title Audion Python Portable Template - Verify Portable Env

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

if not exist "%ROOT%\runtime\python.exe" goto ERR_PYTHON
if not exist "%ROOT%\system_core\doctor.py" goto ERR_DOCTOR

"%ROOT%\runtime\python.exe" "%ROOT%\system_core\doctor.py" --project-root "%ROOT%"
set "RC=%errorlevel%"
if not defined AUDION_NO_PAUSE pause
exit /b %RC%

:ERR_PYTHON
echo [ERROR] runtime\python.exe was not found.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_DOCTOR
echo [ERROR] doctor.py was not found.
if not defined AUDION_NO_PAUSE pause
exit /b 1
