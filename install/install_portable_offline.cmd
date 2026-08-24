@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion Python Portable Template - Offline Install

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "RUNTIME_DIR=%ROOT%\runtime"
set "WHEELHOUSE_DIR=%ROOT%\wheelhouse"
set "REQ_FILE=%ROOT%\install\requirements_full.in"
set "GET_PIP=%ROOT%\install\download\get-pip.py"
set "PYTHON_MINOR=12"

echo ======================================================================
echo   AUDION PYTHON PORTABLE TEMPLATE - OFFLINE INSTALL
echo ======================================================================
echo Root:       %ROOT%
echo Runtime:    %RUNTIME_DIR%
echo Wheelhouse: %WHEELHOUSE_DIR%
echo.

if not exist "%RUNTIME_DIR%\python.exe" goto ERR_PYTHON
if not exist "%REQ_FILE%" goto ERR_REQ
call :PATCH_PTH "%RUNTIME_DIR%\python3%PYTHON_MINOR%._pth"
if errorlevel 1 goto ERR_PTH

"%RUNTIME_DIR%\python.exe" -m pip --version >nul 2>nul
if errorlevel 1 goto NEED_PIP
goto INSTALL

:NEED_PIP
if not exist "%GET_PIP%" goto ERR_GETPIP
echo [1/3] Installing pip from cached get-pip.py...
"%RUNTIME_DIR%\python.exe" "%GET_PIP%"
if errorlevel 1 goto ERR_PIP

:INSTALL
echo [2/3] Installing packages from wheelhouse...
"%RUNTIME_DIR%\python.exe" -m pip install --disable-pip-version-check --no-index --find-links="%WHEELHOUSE_DIR%" -r "%REQ_FILE%"
if errorlevel 1 goto ERR_INSTALL

echo [3/3] Verifying environment...
call "%ROOT%\install\verify_portable_env.cmd"
if errorlevel 1 exit /b %errorlevel%

echo [INFO] Release licensing is generated later from the finalized release contents.
exit /b 0

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

:ERR_PYTHON
echo [ERROR] runtime\python.exe was not found.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_PTH
echo [ERROR] Failed to patch runtime\python3%PYTHON_MINOR%._pth.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_REQ
echo [ERROR] requirements_full.in was not found.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_GETPIP
echo [ERROR] Cached get-pip.py was not found.
echo [INFO] Run Build_Portable_Env_Build.cmd once on an online machine.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_PIP
echo [ERROR] Failed to install pip.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_INSTALL
echo [ERROR] Offline install failed.
if not defined AUDION_NO_PAUSE pause
exit /b 1
