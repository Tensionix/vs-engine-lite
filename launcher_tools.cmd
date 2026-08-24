@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion Python Portable Template - Tools Launcher

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "INSTALL_DIR=%BASE_DIR%\install"
set "LICENSE_DIR=%CORE_DIR%\license"
set "FZF_EXE=%CORE_DIR%\fzf.exe"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\tools_menu.txt"
set "RES_FILE=%RUNTIME_DIR%\tools_menu_res.txt"
set "PYTHON_AVAILABLE="
set "TOOLS_PROMPT=audion@portable-template [TOOLS] > "

if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%" >nul 2>nul
call :RESOLVE_PYTHON

:MAIN
cls
echo ======================================================================
echo   AUDION PYTHON PORTABLE TEMPLATE - TOOLS / SERVICE / RELEASE
echo ======================================================================
if defined PYTHON_AVAILABLE (
  echo Python: %PYTHON_CMD% %PYTHON_ARGS%
) else (
  echo Python: not resolved
)
echo.

if exist "%FZF_EXE%" goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Diagnostic ====================================================
>>"%MENU_FILE%" echo [01] Env doctor                        ^| doctor         ^| verify runtime, plugins, ffmpeg, CUDA
>>"%MENU_FILE%" echo [02] Repair pip shims                  ^| repair_shims   ^| fix Scripts\*.exe shebangs after a project move
>>"%MENU_FILE%" echo [03] CUDA bench                        ^| bench_cuda     ^| pure-pipeline CPU vs CUDA timing on a video
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Licenses / release ============================================
>>"%MENU_FILE%" echo [04] Collect licenses (Python)         ^| collect_py     ^| explicit Python engine
>>"%MENU_FILE%" echo [05] Prune stale license folders       ^| prune_stale    ^| remove uninstalled package leftovers
>>"%MENU_FILE%" echo [06] Deduplicate collected licenses    ^| dedupe         ^| exact content duplicates only
>>"%MENU_FILE%" echo [07] Make release archive              ^| make_release   ^| stage, refresh licenses, archive
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Open folders ==================================================
>>"%MENU_FILE%" echo [08] Open licenses                     ^| open_licenses  ^| explorer
>>"%MENU_FILE%" echo [09] Open release                      ^| open_release   ^| explorer
>>"%MENU_FILE%" echo [10] Open system_core                  ^| open_core      ^| explorer
>>"%MENU_FILE%" echo [11] Open install                      ^| open_install   ^| explorer
>>"%MENU_FILE%" echo [12] Open wheelhouse                   ^| open_wheels    ^| explorer
>>"%MENU_FILE%" echo [00] Back                              ^| back           ^| return

type "%MENU_FILE%" | "%FZF_EXE%" --prompt="%TOOLS_PROMPT%" --pointer=">" --header="Pick tool:" --layout=reverse --border="rounded" --info=hidden --margin=1,2 > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="doctor" goto DOCTOR
if /I "%RAW%"=="repair_shims" goto REPAIR_SHIMS
if /I "%RAW%"=="bench_cuda" goto BENCH_CUDA
if /I "%RAW%"=="collect_py" goto COLLECT_LICENSES_PY
if /I "%RAW%"=="prune_stale" goto PRUNE_STALE_LICENSES
if /I "%RAW%"=="dedupe" goto DEDUPE_LICENSES
if /I "%RAW%"=="make_release" goto MAKE_RELEASE
if /I "%RAW%"=="open_core" goto OPEN_CORE
if /I "%RAW%"=="open_install" goto OPEN_INSTALL
if /I "%RAW%"=="open_wheels" goto OPEN_WHEELS
if /I "%RAW%"=="open_licenses" goto OPEN_LICENSES
if /I "%RAW%"=="open_release" goto OPEN_RELEASE
if /I "%RAW%"=="back" exit /b 0
goto MAIN

:FALLBACK_MENU
echo [1] Env doctor
echo [2] Repair pip shims (after a project move)
echo [3] CUDA bench
echo [4] Collect licenses (Python)
echo [5] Prune stale license folders
echo [6] Deduplicate collected licenses
echo [7] Make release archive
echo [8] Open licenses
echo [9] Open release
echo [A] Open system_core
echo [B] Open install
echo [C] Open wheelhouse
echo [0] Back
echo.
choice /C 123456789ABC0 /N /M "Select: "
if errorlevel 13 exit /b 0
if errorlevel 12 goto OPEN_WHEELS
if errorlevel 11 goto OPEN_INSTALL
if errorlevel 10 goto OPEN_CORE
if errorlevel 9 goto OPEN_RELEASE
if errorlevel 8 goto OPEN_LICENSES
if errorlevel 7 goto MAKE_RELEASE
if errorlevel 6 goto DEDUPE_LICENSES
if errorlevel 5 goto PRUNE_STALE_LICENSES
if errorlevel 4 goto COLLECT_LICENSES_PY
if errorlevel 3 goto BENCH_CUDA
if errorlevel 2 goto REPAIR_SHIMS
if errorlevel 1 goto DOCTOR
goto MAIN

:DOCTOR
call :REQUIRE_PYTHON || goto MAIN
"%PYTHON_CMD%" %PYTHON_ARGS% "%CORE_DIR%\doctor.py"
if not defined AUDION_NO_PAUSE pause
goto MAIN

:REPAIR_SHIMS
call "%INSTALL_DIR%\Repair-PipShims.cmd"
if not defined AUDION_NO_PAUSE pause
goto MAIN

:BENCH_CUDA
echo.
echo Drag a video file here, or paste its path, then press Enter.
echo (Empty input cancels.)
set "BENCH_SRC="
set /p BENCH_SRC=Source video:
set "BENCH_SRC=%BENCH_SRC:"=%"
if not defined BENCH_SRC goto MAIN
if not exist "%BENCH_SRC%" (
  echo [ERROR] File not found: %BENCH_SRC%
  if not defined AUDION_NO_PAUSE pause & goto MAIN
)
call "%INSTALL_DIR%\Bench-CUDA.cmd" "%BENCH_SRC%"
goto MAIN

:COLLECT_LICENSES_PY
call "%LICENSE_DIR%\Run-Collect-ThirdPartyLicenses-Python.cmd"
goto MAIN

:PRUNE_STALE_LICENSES
call "%LICENSE_DIR%\Run-Prune-Stale-ThirdPartyLicenses.cmd"
goto MAIN

:DEDUPE_LICENSES
call "%LICENSE_DIR%\Run-Deduplicate-ThirdPartyLicenses.cmd"
goto MAIN

:MAKE_RELEASE
call "%INSTALL_DIR%\make_release_archive.cmd"
goto MAIN

:OPEN_CORE
start "" explorer "%CORE_DIR%"
goto MAIN

:OPEN_INSTALL
start "" explorer "%INSTALL_DIR%"
goto MAIN

:OPEN_WHEELS
start "" explorer "%BASE_DIR%\wheelhouse"
goto MAIN

:OPEN_LICENSES
if not exist "%BASE_DIR%\licenses" mkdir "%BASE_DIR%\licenses" >nul 2>nul
start "" explorer "%BASE_DIR%\licenses"
goto MAIN

:OPEN_RELEASE
if not exist "%BASE_DIR%\release" mkdir "%BASE_DIR%\release" >nul 2>nul
start "" explorer "%BASE_DIR%\release"
goto MAIN

:REQUIRE_PYTHON
if defined PYTHON_AVAILABLE exit /b 0
echo [ERROR] Python runtime was not resolved.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:RESOLVE_PYTHON
set "PYTHON_CMD="
set "PYTHON_ARGS="
set "PYTHON_AVAILABLE="
if exist "%BASE_DIR%\runtime\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python.exe"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
if exist "%BASE_DIR%\runtime\python\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python\python.exe"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
py -3.12 -V >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=py"
  set "PYTHON_ARGS=-3.12"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
py -3 -V >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=py"
  set "PYTHON_ARGS=-3"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
where python.exe >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=python"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
where python3.exe >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=python3"
  set "PYTHON_AVAILABLE=1"
  goto :eof
)
goto :eof

:TRIM
set "_TMP=!%~1!"
for /f "tokens=* delims= " %%z in ("!_TMP!") do set "_TMP=%%z"
:TRIM_R
if not defined _TMP goto TRIM_DONE
if not "!_TMP:~-1!"==" " goto TRIM_DONE
set "_TMP=!_TMP:~0,-1!"
goto TRIM_R
:TRIM_DONE
set "%~1=!_TMP!"
goto :eof
