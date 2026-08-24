@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Film Looks (English)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\film_looks_menu_en.txt"
set "RES_FILE=%RUNTIME_DIR%\film_looks_menu_en_res.txt"

if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%" >nul 2>nul

call :RESOLVE_PYTHON
if errorlevel 1 goto NO_PYTHON

call :RESOLVE_FZF
if errorlevel 1 (
  set "MENU_MODE=CMD fallback"
) else (
  set "MENU_MODE=FZF"
)

:MAIN
cls
echo ======================================================================
echo   AUDION VS ENGINE - FILM LOOKS  (cinematic emulations)
echo ======================================================================
echo Root:      %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Menu mode: %MENU_MODE%
echo Tip:       intensity 0.0 = off, 1.0 = tuned, 2.0 = heavy
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Film looks (subtle -^> heavy) ====================================
>>"%MENU_FILE%" echo [01] Cinematic                   ^| cinematic       ^| universal subtle filmic, safe default
>>"%MENU_FILE%" echo [02] Film 35mm                   ^| film_35mm       ^| Kodak 250D / 500T / 50D variants
>>"%MENU_FILE%" echo [03] Film 16mm                   ^| film_16mm       ^| organic, grainier, lifted blacks
>>"%MENU_FILE%" echo [04] Super 8                     ^| super8          ^| heaviest grain, softest, faded 70s
>>"%MENU_FILE%" echo [05] Bleach bypass               ^| bleach_bypass   ^| high contrast, desaturated, harsh
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Tools ===========================================================
>>"%MENU_FILE%" echo [06] List encoders               ^| list_encoders   ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [07] Doctor                      ^| doctor          ^| full stack health
>>"%MENU_FILE%" echo [08] Open input folder           ^| open_input      ^| Explorer
>>"%MENU_FILE%" echo [09] Open output folder          ^| open_output     ^| Explorer
>>"%MENU_FILE%" echo [10] Open logs folder            ^| open_logs       ^| JSON reports
>>"%MENU_FILE%" echo [00] Back / Exit                 ^| exit            ^| close

"%FZF_CMD%" --prompt="audion@film-looks > " --pointer=">" --header="From subtle (cinematic) to extreme (super8). Pick a look." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="cinematic"     goto CINEMATIC
if /I "%RAW%"=="film_35mm"     goto FILM_35MM
if /I "%RAW%"=="film_16mm"     goto FILM_16MM
if /I "%RAW%"=="super8"        goto SUPER8
if /I "%RAW%"=="bleach_bypass" goto BLEACH_BYPASS
if /I "%RAW%"=="list_encoders" goto LIST_ENCODERS
if /I "%RAW%"=="doctor"        goto DOCTOR
if /I "%RAW%"=="open_input"    goto OPEN_INPUT
if /I "%RAW%"=="open_output"   goto OPEN_OUTPUT
if /I "%RAW%"=="open_logs"     goto OPEN_LOGS
if /I "%RAW%"=="exit"          exit /b 0
goto MAIN

:FALLBACK_MENU
echo === FILM LOOKS ===
echo [1] Cinematic            (subtle, safe default)
echo [2] Film 35mm            (Kodak 250D / 500T / 50D)
echo [3] Film 16mm            (organic, grainier)
echo [4] Super 8              (heaviest, faded 70s)
echo [5] Bleach bypass        (high contrast, desat)
echo.
echo === TOOLS ===
echo [6] List encoders
echo [7] Doctor
echo [8] Open input folder
echo [9] Open output folder
echo [A] Open logs folder
echo [0] Back / Exit
echo.
choice /C 123456789A0 /N /M "Select: "
if errorlevel 11 exit /b 0
if errorlevel 10 goto OPEN_LOGS
if errorlevel 9  goto OPEN_OUTPUT
if errorlevel 8  goto OPEN_INPUT
if errorlevel 7  goto DOCTOR
if errorlevel 6  goto LIST_ENCODERS
if errorlevel 5  goto BLEACH_BYPASS
if errorlevel 4  goto SUPER8
if errorlevel 3  goto FILM_16MM
if errorlevel 2  goto FILM_35MM
if errorlevel 1  goto CINEMATIC
goto MAIN


REM =====================================================================
REM Preset actions
REM =====================================================================

:CINEMATIC
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE cinematic
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET cinematic --intensity %INTENSITY%
goto MAIN

:FILM_35MM
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE film_35mm
call :ASK_STOCK
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET film_35mm --stock %STOCK% --intensity %INTENSITY%
goto MAIN

:FILM_16MM
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE film_16mm
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET film_16mm --intensity %INTENSITY%
goto MAIN

:SUPER8
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE super8
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET super8 --intensity %INTENSITY%
goto MAIN

:BLEACH_BYPASS
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE bleach_bypass
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET bleach_bypass --intensity %INTENSITY%
goto MAIN

:LIST_ENCODERS
call :RUNPY "%CORE_DIR%\main.py" list-encoders
if not defined AUDION_NO_PAUSE pause
goto MAIN

:DOCTOR
call :RUNPY "%CORE_DIR%\doctor.py"
if not defined AUDION_NO_PAUSE pause
goto MAIN

:OPEN_INPUT
start "" explorer "%BASE_DIR%\input"
goto MAIN

:OPEN_OUTPUT
start "" explorer "%BASE_DIR%\output"
goto MAIN

:OPEN_LOGS
start "" explorer "%BASE_DIR%\logs"
goto MAIN


REM =====================================================================
REM Param prompts
REM =====================================================================

:ASK_INPUT_FILE
set "SRC_PATH="
echo.
echo [INFO] Press Enter to use the project input folder, or type a file/folder path.
set /p SRC_PATH=Input file or folder [input] :
if not defined SRC_PATH set "SRC_PATH=%BASE_DIR%\input"
goto :eof

:ASK_OUTPUT_FILE
set "DST_PATH="
echo.
set /p DST_PATH=Output file [output\out_%~1.mp4] :
if not defined DST_PATH set "DST_PATH=%BASE_DIR%\output\out_%~1.mp4"
goto :eof

:ASK_INTENSITY
set "INTENSITY="
echo.
echo Master intensity (scales grain, halation, optical softness):
echo   1 - 0.5  (subtle / safe)
echo   2 - 1.0  (tuned default)
echo   3 - 1.5  (visible)
echo   4 - 2.0  (heavy)
set /p INTENSITY=Select or type number [2] :
if not defined INTENSITY set "INTENSITY=1.0"
if /I "%INTENSITY%"=="1" set "INTENSITY=0.5"
if /I "%INTENSITY%"=="2" set "INTENSITY=1.0"
if /I "%INTENSITY%"=="3" set "INTENSITY=1.5"
if /I "%INTENSITY%"=="4" set "INTENSITY=2.0"
goto :eof

:ASK_STOCK
set "STOCK="
echo.
echo Kodak 35mm stock variant:
echo   1 - 250D   (daylight, neutral, fine grain) -- default
echo   2 - 500T   (tungsten, faster, cooler tilt)
echo   3 - 50D    (daylight, cleanest grain)
set /p STOCK=Select [1] :
if not defined STOCK set "STOCK=250D"
if /I "%STOCK%"=="1" set "STOCK=250D"
if /I "%STOCK%"=="2" set "STOCK=500T"
if /I "%STOCK%"=="3" set "STOCK=50D"
goto :eof

:ASK_ENCODER
set "ENCODER="
echo.
echo Output encoder profile:
echo   1 - h264_crf14       (default, semi-lossless, archive grade)
echo   2 - h264_crf17       (almost invisible lossy, Audion tier)
echo   3 - h264_crf21       (web / proxy / preview)
echo   4 - h265_crf17       (HEVC, smaller files at same quality)
echo   5 - prores_lt        (default ProRes; grading / round-trip)
echo   6 - prores_lt_mxf    (ProRes LT in MXF wrapper for Adobe / Avid)
echo   7 - h264_nvenc_q14   (NVIDIA hardware encode; CPU-free)
echo   8 - h265_nvenc_q17   (NVIDIA hardware HEVC; 10-bit p010le)
set /p ENCODER=Select [1] :
if not defined ENCODER set "ENCODER=h264_crf14"
if /I "%ENCODER%"=="1" set "ENCODER=h264_crf14"
if /I "%ENCODER%"=="2" set "ENCODER=h264_crf17"
if /I "%ENCODER%"=="3" set "ENCODER=h264_crf21"
if /I "%ENCODER%"=="4" set "ENCODER=h265_crf17"
if /I "%ENCODER%"=="5" set "ENCODER=prores_lt"
if /I "%ENCODER%"=="6" set "ENCODER=prores_lt_mxf"
if /I "%ENCODER%"=="7" set "ENCODER=h264_nvenc_q14"
if /I "%ENCODER%"=="8" set "ENCODER=h265_nvenc_q17"
goto :eof


REM =====================================================================
REM Run engine
REM =====================================================================

:RUN_PRESET
set "PRESET=%~1"
shift
set "EXTRA="
:RUN_PRESET_LOOP
if "%~1"=="" goto RUN_PRESET_GO
set "EXTRA=%EXTRA% %~1"
shift
goto RUN_PRESET_LOOP
:RUN_PRESET_GO
echo.
echo [run] film_looks/%PRESET%
echo       input:   %SRC_PATH%
echo       output:  %DST_PATH%
echo       encoder: %ENCODER%
echo.
call :RUNPY "%CORE_DIR%\main.py" run --palette film_looks --preset %PRESET% --input "%SRC_PATH%" --output "%DST_PATH%" --encoder %ENCODER%%EXTRA%
echo.
if not defined AUDION_NO_PAUSE pause
goto :eof


REM =====================================================================
REM Plumbing
REM =====================================================================

:NO_PYTHON
cls
echo [ERROR] Python orchestrator runtime was not resolved.
echo Expected: runtime\python.exe
echo Run builder_main.cmd -^> [01] BUILD PORTABLE ENV first.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:RUNPY
set "TARGET=%~1"
if not exist "%TARGET%" (
  echo [ERROR] Python script not found:
  echo %TARGET%
  goto :eof
)
"%PYTHON_CMD%" %PYTHON_ARGS% %*
goto :eof

:RESOLVE_PYTHON
set "PYTHON_CMD="
set "PYTHON_ARGS="
if exist "%BASE_DIR%\runtime\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python.exe"
  goto PY_OK
)
if exist "%BASE_DIR%\runtime\python\python.exe" (
  set "PYTHON_CMD=%BASE_DIR%\runtime\python\python.exe"
  goto PY_OK
)
py -3.12 -V >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=py"
  set "PYTHON_ARGS=-3.12"
  goto PY_OK
)
where python >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_CMD=python"
  goto PY_OK
)
exit /b 1
:PY_OK
exit /b 0

:RESOLVE_FZF
set "FZF_CMD="
if /I "%AUDION_DISABLE_FZF%"=="1" exit /b 1
if exist "%CORE_DIR%\fzf.exe" (
  set "FZF_CMD=%CORE_DIR%\fzf.exe"
  exit /b 0
)
where fzf >nul 2>nul
if not errorlevel 1 (
  set "FZF_CMD=fzf"
  exit /b 0
)
exit /b 1

:TRIM
for /f "tokens=* delims= " %%z in ("!%~1!") do set "%~1=%%z"
:TRIM_R
if "!%~1:~-1!"==" " set "%~1=!%~1:~0,-1!" & goto TRIM_R
goto :eof
