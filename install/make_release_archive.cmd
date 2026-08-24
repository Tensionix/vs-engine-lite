@echo off
setlocal EnableExtensions

title Audion Python Portable Template - Make Release Archive

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"
for %%A in ("%ROOT%") do set "PROJECT_NAME=%%~nxA"

set "RELEASE_DIR=%ROOT%\release"
set "STAGE_PARENT=%RELEASE_DIR%\_stage"
set "STAGE_PROJECT=%STAGE_PARENT%\%PROJECT_NAME%"
set "ARCHIVE=%RELEASE_DIR%\%PROJECT_NAME%_portable.zip"
set "NOTICES=%STAGE_PROJECT%\licenses\THIRD_PARTY_NOTICES.md"
set "LICENSES_DIR=%STAGE_PROJECT%\licenses"

if not exist "%RELEASE_DIR%\" mkdir "%RELEASE_DIR%" >nul 2>nul
if exist "%STAGE_PROJECT%\" rd /s /q "%STAGE_PROJECT%" >nul 2>nul
if not exist "%STAGE_PARENT%\" mkdir "%STAGE_PARENT%" >nul 2>nul

call :BANNER
call :CHECKLIST_START

echo [1/6] Staging finalized release contents...
robocopy "%ROOT%" "%STAGE_PROJECT%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD "%ROOT%\.git" "%ROOT%\release" "%ROOT%\.venv" "%ROOT%\venv" "%ROOT%\__pycache__" "%ROOT%\output" "%ROOT%\logs" "%ROOT%\._runtime" "%ROOT%\install\download" /XF "%ROOT%\api_key.txt" "%ROOT%\api_key_openai.txt" "%ROOT%\MEMORY.md" >nul
set "RC=%errorlevel%"
if %RC% GEQ 8 goto ERR_STAGE

echo [2/6] Verifying release staging directory...
if not exist "%STAGE_PROJECT%\" goto ERR_STAGE
if not exist "%STAGE_PROJECT%\install\" goto ERR_STAGE
if not exist "%STAGE_PROJECT%\system_core\license\" goto ERR_STAGE

echo [3/6] Generating and deduplicating third-party notices from staged release with the Python engine...
if exist "%STAGE_PROJECT%\system_core\license\Run-Collect-And-Deduplicate-ThirdPartyLicenses.cmd" (
  call "%STAGE_PROJECT%\system_core\license\Run-Collect-And-Deduplicate-ThirdPartyLicenses.cmd" /CLEAN /NOPAUSE
  if errorlevel 1 goto ERR_LICENSES
) else if exist "%STAGE_PROJECT%\system_core\license\collect_third_party_licenses.py" (
  set "STAGE_PY="
  if exist "%STAGE_PROJECT%\runtime\python.exe" (
    set "STAGE_PY=%STAGE_PROJECT%\runtime\python.exe"
    set "STAGE_PY_ARGS="
  ) else if exist "%STAGE_PROJECT%\runtime\python\python.exe" (
    set "STAGE_PY=%STAGE_PROJECT%\runtime\python\python.exe"
    set "STAGE_PY_ARGS="
  ) else (
    set "STAGE_PY=python"
    set "STAGE_PY_ARGS="
  )
  "%STAGE_PY%" %STAGE_PY_ARGS% "%STAGE_PROJECT%\system_core\license\collect_third_party_licenses.py" --project-root "%STAGE_PROJECT%" --output-root "%STAGE_PROJECT%" --clean-output
  if errorlevel 1 goto ERR_LICENSES
  "%STAGE_PY%" %STAGE_PY_ARGS% "%STAGE_PROJECT%\system_core\license\deduplicate_collected_licenses.py" --project-root "%STAGE_PROJECT%" --output-root "%STAGE_PROJECT%"
  if errorlevel 1 goto ERR_LICENSES
) else if exist "%STAGE_PROJECT%\system_core\license\Run-Collect-ThirdPartyLicenses.cmd" (
  call "%STAGE_PROJECT%\system_core\license\Run-Collect-ThirdPartyLicenses.cmd" /CLEAN /NOPAUSE
  if errorlevel 1 goto ERR_LICENSES
) else (
  echo [ERROR] Staged system_core\license collector was not found.
  goto ERR_LICENSES
)

echo [4/6] Checking required release licensing outputs...
if not exist "%NOTICES%" goto ERR_LICENSES_OUTPUT
if not exist "%LICENSES_DIR%\" goto ERR_LICENSES_OUTPUT

echo [5/6] Building final ZIP archive for GitHub Releases...
where tar.exe >nul 2>nul
if errorlevel 1 goto ERR_ARCHIVE
if exist "%ARCHIVE%" del /f /q "%ARCHIVE%" >nul 2>nul
pushd "%STAGE_PARENT%" >nul
tar.exe -a -cf "%ARCHIVE%" "%PROJECT_NAME%"
set "RC=%errorlevel%"
popd >nul
if not "%RC%"=="0" goto ERR_ARCHIVE

echo [6/6] Release archive created successfully.
call :CHECKLIST_FINISH
if not defined AUDION_NO_PAUSE pause
exit /b 0

:BANNER
echo ======================================================================
echo   AUDION PYTHON PORTABLE TEMPLATE - MAKE RELEASE ARCHIVE
echo ======================================================================
echo Root:    %ROOT%
echo Stage:   %STAGE_PROJECT%
echo Target:  %ARCHIVE%
echo.
goto :eof

:CHECKLIST_START
echo Release gate:
echo   - Build the final package first
echo   - Stage only real release contents
echo   - Generate licenses from staged contents
echo   - Archive only after licensing is complete
echo.
goto :eof

:CHECKLIST_FINISH
echo.
echo GitHub release checklist:
echo   [OK] Final package staged
echo   [OK] licenses\THIRD_PARTY_NOTICES.md generated
echo   [OK] licenses\ folder generated
echo   [OK] ZIP archive created for GitHub Releases
echo.
echo Manual review before upload:
echo   - Open the ZIP and inspect top-level contents
echo   - Verify no secrets or private configs are present
echo   - Verify build-only tools did not leak into release by accident
echo   - Verify launchers start and main workflow passes smoke test
echo   - Upload the ZIP as a Release asset, not as repository source
if exist "%NOTICES%" echo   - Review: %NOTICES%
if exist "%ARCHIVE%" echo   - Archive: %ARCHIVE%
echo.
goto :eof

:ERR_STAGE
echo.
echo [ERROR] Failed to stage release contents.
echo Check project paths, exclusions, and release structure.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_LICENSES
echo.
echo [ERROR] Third-party license generation failed on staged release contents.
echo Fix the Python licensing step before publishing any GitHub Release.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_LICENSES_OUTPUT
echo.
echo [ERROR] Licensing step completed without required outputs.
echo Expected:
echo   - %NOTICES%
echo   - %LICENSES_DIR%
if not defined AUDION_NO_PAUSE pause
exit /b 1

:ERR_ARCHIVE
echo.
echo [ERROR] Failed to create release archive.
echo Verify tar.exe availability and release folder permissions.
if not defined AUDION_NO_PAUSE pause
exit /b 1
