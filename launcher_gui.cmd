@echo off
chcp 65001 >nul
setlocal EnableExtensions
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

title Audion VS Engine Lite - GUI

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "APP_FILE=%BASE_DIR%\system_core\ui_nicegui\window.py"

call :RESOLVE_PYTHON
if errorlevel 1 goto NO_PYTHON

if /I "%AUDION_GUI_RESOLVE_ONLY%"=="1" exit /b 0

if not exist "%APP_FILE%" goto NO_APP

if /I "%PYTHON_IS_WINDOWED%"=="1" (
  start "" "%PYTHON_CMD%" %PYTHON_ARGS% "%APP_FILE%"
  exit /b 0
)

"%PYTHON_CMD%" %PYTHON_ARGS% "%APP_FILE%"
exit /b %ERRORLEVEL%

:RESOLVE_PYTHON
set "PYTHON_CMD="
set "PYTHON_ARGS="
set "PYTHON_IS_WINDOWED="

if /I not "%AUDION_GUI_CONSOLE%"=="1" if exist "%BASE_DIR%\runtime\pythonw.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\pythonw.exe"
  set "PYTHON_IS_WINDOWED=1"
  exit /b 0
)

if exist "%BASE_DIR%\runtime\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python.exe"
  exit /b 0
)

if /I not "%AUDION_GUI_CONSOLE%"=="1" if exist "%BASE_DIR%\runtime\python\pythonw.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python\pythonw.exe"
  set "PYTHON_IS_WINDOWED=1"
  exit /b 0
)

if exist "%BASE_DIR%\runtime\python\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python\python.exe"
  exit /b 0
)

py -3.12 -V >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=py"
  set "PYTHON_ARGS=-3.12"
  exit /b 0
)

exit /b 1

:NO_APP
echo [ERROR] GUI wrapper was not found:
echo %APP_FILE%
if not defined AUDION_NO_PAUSE pause
exit /b 1

:NO_PYTHON
echo [ERROR] Python runtime was not resolved.
echo Supported locations:
echo   runtime\pythonw.exe
echo   runtime\python.exe
echo   runtime\python\pythonw.exe
echo   runtime\python\python.exe
echo   py -3.12
echo.
echo Build the portable runtime first or run this launcher from the project root.
echo Set AUDION_GUI_CONSOLE=1 to run GUI in console debug mode.
if not defined AUDION_NO_PAUSE pause
exit /b 1

