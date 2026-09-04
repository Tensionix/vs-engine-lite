@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine Lite - project cleanup

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%" || exit /b 1

set "AUTO_YES=0"
set "NO_PAUSE=0"
for %%A in (%*) do (
  if /I "%%~A"=="/Y" set "AUTO_YES=1"
  if /I "%%~A"=="/YES" set "AUTO_YES=1"
  if /I "%%~A"=="--yes" set "AUTO_YES=1"
  if /I "%%~A"=="/NOPAUSE" set "NO_PAUSE=1"
  if /I "%%~A"=="--no-pause" set "NO_PAUSE=1"
)

echo ======================================================================
echo   AUDION VS ENGINE LITE - PROJECT CLEANUP
echo ======================================================================
echo Root: %BASE_DIR%
echo.
echo This prepares the lightweight source-only tree.
echo It keeps scripts, docs, git service files, config folders and source presets.
echo It removes portable runtimes, downloaded tools, caches, logs, reports,
echo media input/output, smoke artifacts and generated release artifacts.
echo.
echo Removed heavy/runtime trees:
echo   runtime\                     embedded GUI Python
echo   wheelhouse\                  Python package cache
echo   Tools\ffmpeg\                portable FFmpeg binaries/docs
echo   system_core\vapoursynth\     portable VapourSynth runtime/plugins
echo   system_core\powershell\      portable PowerShell runtime
echo   system_core\7zip\            bootstrapped 7-Zip helper binaries
echo   install\download\            installer download cache
echo.
echo Cleared generated state:
echo   input\ output\ logs\ report\ release\ data\ ._runtime\
echo   root *.log, api_key*.txt, __pycache__, *.pyc, *.pyo
echo   dev caches: .pytest_cache, .mypy_cache, .ruff_cache, htmlcov
echo   scratch files: *.tmp, *.temp, *.bak, *.old, *.orig
echo.
echo Kept:
echo   *.cmd, *.ps1, *.py, *.vpy, docs, config\, config\profiles\
echo   .gitignore, and the empty service folders created by install\init_folders.cmd
echo.
echo IMPORTANT: launchers will need the installer scripts again after this cleanup.
echo.
if "%AUTO_YES%"=="1" goto clean
choice /C YNQ /N /M "Proceed with project cleanup? [Y/N/Q]: "
if errorlevel 3 goto quit
if errorlevel 2 goto cancelled
if errorlevel 1 goto clean
goto cancelled

:clean
set "REMOVED=0"

call :REMOVE_TREE "%BASE_DIR%\runtime" "runtime"
call :REMOVE_TREE "%BASE_DIR%\wheelhouse" "wheelhouse"
call :REMOVE_TREE "%BASE_DIR%\._runtime" "._runtime"
call :REMOVE_TREE "%BASE_DIR%\data" "data"
call :REMOVE_TREE "%BASE_DIR%\input" "input"
call :REMOVE_TREE "%BASE_DIR%\output" "output"
call :REMOVE_TREE "%BASE_DIR%\logs" "logs"
call :REMOVE_TREE "%BASE_DIR%\report" "report"
call :REMOVE_TREE "%BASE_DIR%\release" "release"
call :REMOVE_TREE "%BASE_DIR%\install\download" "install\download"

call :REMOVE_TREE "%BASE_DIR%\Tools\ffmpeg" "Tools\ffmpeg"
call :REMOVE_FILE "%BASE_DIR%\Tools\ffmpeg-*-source.tar.gz" "Tools\ffmpeg-*-source.tar.gz"
call :REMOVE_TREE "%BASE_DIR%\system_core\vapoursynth" "system_core\vapoursynth"
call :REMOVE_TREE "%BASE_DIR%\system_core\powershell" "system_core\powershell"
call :REMOVE_TREE "%BASE_DIR%\system_core\7zip" "system_core\7zip"
call :REMOVE_TREE "%BASE_DIR%\system_core\_ffmpeg_tmp" "system_core\_ffmpeg_tmp"
call :REMOVE_TREE "%BASE_DIR%\system_core\_ffmpeg_btbn_tmp" "system_core\_ffmpeg_btbn_tmp"
call :REMOVE_TREE "%BASE_DIR%\system_core\_fzf_tmp" "system_core\_fzf_tmp"
call :REMOVE_TREE "%BASE_DIR%\system_core\_pwsh_tmp" "system_core\_pwsh_tmp"
call :REMOVE_TREE "%BASE_DIR%\system_core\_powershell_tmp" "system_core\_powershell_tmp"

call :REMOVE_TREE "%BASE_DIR%\.pytest_cache" ".pytest_cache"
call :REMOVE_TREE "%BASE_DIR%\.mypy_cache" ".mypy_cache"
call :REMOVE_TREE "%BASE_DIR%\.ruff_cache" ".ruff_cache"
call :REMOVE_TREE "%BASE_DIR%\.cache" ".cache"
call :REMOVE_TREE "%BASE_DIR%\htmlcov" "htmlcov"

call :REMOVE_FILE "%BASE_DIR%\system_core\fzf.exe" "system_core\fzf.exe"
call :REMOVE_FILE "%BASE_DIR%\api_key.txt" "api_key.txt"
call :REMOVE_FILE "%BASE_DIR%\api_key_openai.txt" "api_key_openai.txt"
for %%F in ("%BASE_DIR%\*.log") do (
  if exist "%%~fF" (
    del /f /q "%%~fF" >nul 2>nul
    if not exist "%%~fF" (
      set /a REMOVED+=1
      echo [OK] Removed %%~nxF
    ) else (
      echo [WARN] Could not remove %%~fF
    )
  )
)

for /d /r "%BASE_DIR%" %%D in (__pycache__) do (
  if exist "%%~fD\" (
    rd /s /q "%%~fD" >nul 2>nul
    if not exist "%%~fD\" set /a REMOVED+=1
  )
)
echo [OK] Cleared __pycache__ folders

for /r "%BASE_DIR%" %%F in (*.pyc *.pyo) do (
  if exist "%%~fF" (
    del /f /q "%%~fF" >nul 2>nul
    if not exist "%%~fF" set /a REMOVED+=1
  )
)
echo [OK] Cleared Python bytecode files

for /r "%BASE_DIR%" %%F in (*.tmp *.temp *.bak *.old *.orig .coverage coverage.xml) do (
  if exist "%%~fF" (
    del /f /q "%%~fF" >nul 2>nul
    if not exist "%%~fF" set /a REMOVED+=1
  )
)
echo [OK] Cleared scratch/test report files

if exist "%BASE_DIR%\install\init_folders.cmd" (
  call "%BASE_DIR%\install\init_folders.cmd"
) else (
  echo [WARN] install\init_folders.cmd not found; placeholders were not recreated.
)

echo.
echo [DONE] Project cleanup finished. Removed approximately %REMOVED% items.
echo The tree is now intended to contain only source scripts, docs, configs
echo and empty service folders.
echo.
call :WAIT_IF_NEEDED
exit /b 0

:cancelled
echo.
echo [CANCELLED] Nothing was deleted.
call :WAIT_IF_NEEDED
exit /b 0

:quit
echo.
echo [QUIT] Nothing was deleted.
call :WAIT_IF_NEEDED
exit /b 0

:REMOVE_TREE
if exist "%~1\" (
  rd /s /q "%~1" >nul 2>nul
  if exist "%~1\" (
    echo [WARN] Could not remove %~2
  ) else (
    set /a REMOVED+=1
    echo [OK] Removed %~2\
  )
)
goto :eof

:REMOVE_FILE
if exist "%~1" (
  del /f /q "%~1" >nul 2>nul
  if exist "%~1" (
    echo [WARN] Could not remove %~2
  ) else (
    set /a REMOVED+=1
    echo [OK] Removed %~2
  )
)
goto :eof

:WAIT_IF_NEEDED
if "%AUTO_YES%"=="1" goto :eof
if "%NO_PAUSE%"=="1" goto :eof
call :WAIT_KEY
goto :eof

:WAIT_KEY
echo Press any key to continue . . .
if not defined AUDION_NO_PAUSE pause >nul
goto :eof
