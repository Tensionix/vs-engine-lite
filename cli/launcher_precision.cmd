@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Precision Engine (English)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\precision_menu_en.txt"
set "RES_FILE=%RUNTIME_DIR%\precision_menu_en_res.txt"

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
echo   AUDION VS ENGINE - PRECISION  (denoise / deband / grain)
echo ======================================================================
echo Root:      %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Menu mode: %MENU_MODE%
echo Pipeline:  Stage 1 Denoise -^> Stage 2 Deband -^> Stage 3 Compositions
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Stage 1 -- Denoise (clean first) ===============================
>>"%MENU_FILE%" echo [01] Mild denoise                          ^| mild_denoise         ^| DFTTest, universal, light/medium/strong
>>"%MENU_FILE%" echo [02] Shadow denoise SOTA  *flagship*       ^| shadow_denoise_sota  ^| BM3D in shadow zone only (CUDA-^>CPU)
>>"%MENU_FILE%" echo [03] Chroma cleanup                        ^| chroma_cleanup       ^| DFTTest on chroma planes only
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Stage 2 -- Deband (smooth gradients) ===========================
>>"%MENU_FILE%" echo [04] Deband safe                           ^| deband_safe          ^| neo_f3kdb light, no grain
>>"%MENU_FILE%" echo [05] Deband + fine grain                   ^| deband_fine_grain    ^| neo_f3kdb + AddGrain restore
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Stage 3 -- Compositions (full chains) ==========================
>>"%MENU_FILE%" echo [06] Filmic rebuild       *flagship*       ^| filmic_rebuild       ^| denoise -^> deband -^> luma-zoned grain
>>"%MENU_FILE%" echo [07] Archive clean                         ^| archive_clean        ^| neutral master, no grain
>>"%MENU_FILE%" echo [08] Pre-grade prep                        ^| pregrade_prep        ^| minimum-touch for Resolve handoff
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Tools ==========================================================
>>"%MENU_FILE%" echo [09] List encoders                         ^| list_encoders        ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [10] Doctor (full stack health)            ^| doctor               ^| VS / plugins / FFmpeg / CUDA
>>"%MENU_FILE%" echo [11] Probe a file                          ^| probe                ^| ffprobe summary (JSON)
>>"%MENU_FILE%" echo [12] Open input folder                     ^| open_input           ^| Explorer
>>"%MENU_FILE%" echo [13] Open output folder                    ^| open_output          ^| Explorer
>>"%MENU_FILE%" echo [14] Open logs folder                      ^| open_logs            ^| JSON reports
>>"%MENU_FILE%" echo [00] Back / Exit                           ^| exit                 ^| close

"%FZF_CMD%" --prompt="audion@precision > " --pointer=">" --header="Stage 1 (denoise) -> Stage 2 (deband) -> Stage 3 (compose). Pick an action." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="mild_denoise"        goto MILD_DENOISE
if /I "%RAW%"=="shadow_denoise_sota" goto SHADOW_DENOISE_SOTA
if /I "%RAW%"=="chroma_cleanup"      goto CHROMA_CLEANUP
if /I "%RAW%"=="deband_safe"         goto DEBAND_SAFE
if /I "%RAW%"=="deband_fine_grain"   goto DEBAND_FINE_GRAIN
if /I "%RAW%"=="filmic_rebuild"      goto FILMIC_REBUILD
if /I "%RAW%"=="archive_clean"       goto ARCHIVE_CLEAN
if /I "%RAW%"=="pregrade_prep"       goto PREGRADE_PREP
if /I "%RAW%"=="list_encoders"       goto LIST_ENCODERS
if /I "%RAW%"=="doctor"              goto DOCTOR
if /I "%RAW%"=="probe"               goto PROBE
if /I "%RAW%"=="open_input"          goto OPEN_INPUT
if /I "%RAW%"=="open_output"         goto OPEN_OUTPUT
if /I "%RAW%"=="open_logs"           goto OPEN_LOGS
if /I "%RAW%"=="exit"                exit /b 0
goto MAIN

:FALLBACK_MENU
echo === STAGE 1 -- DENOISE ===
echo [1] Mild denoise               (DFTTest universal)
echo [2] Shadow denoise SOTA  *     (BM3D shadow-mask)
echo [3] Chroma cleanup             (DFTTest chroma-only)
echo.
echo === STAGE 2 -- DEBAND ===
echo [4] Deband safe                (neo_f3kdb light)
echo [5] Deband + fine grain        (neo_f3kdb + AddGrain)
echo.
echo === STAGE 3 -- COMPOSITIONS ===
echo [6] Filmic rebuild       *     (denoise -^> deband -^> zoned grain)
echo [7] Archive clean              (neutral master)
echo [8] Pre-grade prep             (Resolve handoff)
echo.
echo === TOOLS ===
echo [9] List encoders
echo [A] Doctor
echo [B] Probe a file
echo [C] Open input folder
echo [D] Open output folder
echo [E] Open logs folder
echo [0] Back / Exit
echo.
choice /C 123456789ABCDE0 /N /M "Select: "
if errorlevel 15 exit /b 0
if errorlevel 14 goto OPEN_LOGS
if errorlevel 13 goto OPEN_OUTPUT
if errorlevel 12 goto OPEN_INPUT
if errorlevel 11 goto PROBE
if errorlevel 10 goto DOCTOR
if errorlevel 9  goto LIST_ENCODERS
if errorlevel 8  goto PREGRADE_PREP
if errorlevel 7  goto ARCHIVE_CLEAN
if errorlevel 6  goto FILMIC_REBUILD
if errorlevel 5  goto DEBAND_FINE_GRAIN
if errorlevel 4  goto DEBAND_SAFE
if errorlevel 3  goto CHROMA_CLEANUP
if errorlevel 2  goto SHADOW_DENOISE_SOTA
if errorlevel 1  goto MILD_DENOISE
goto MAIN


REM =====================================================================
REM Preset actions
REM =====================================================================

:MILD_DENOISE
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE mild_denoise
call :ASK_STRENGTH
call :ASK_ENCODER
call :RUN_PRESET mild_denoise --strength %STRENGTH%
goto MAIN

:SHADOW_DENOISE_SOTA
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE shadow_denoise_sota
call :ASK_SIGMA 2.5
call :ASK_GRAIN_BACK
call :ASK_SHADOW_THRESHOLD
call :ASK_ENCODER
call :RUN_PRESET shadow_denoise_sota --sigma %SIGMA% --grain-back %GRAIN_BACK% --shadow-threshold %SHADOW_THRESHOLD%
goto MAIN

:CHROMA_CLEANUP
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE chroma_cleanup
call :ASK_STRENGTH
call :ASK_ENCODER
call :RUN_PRESET chroma_cleanup --strength %STRENGTH%
goto MAIN

:DEBAND_SAFE
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE deband_safe
call :ASK_DEBAND_RANGE 12
call :ASK_ENCODER
call :RUN_PRESET deband_safe --range %DEBAND_RANGE%
goto MAIN

:DEBAND_FINE_GRAIN
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE deband_fine_grain
call :ASK_DEBAND_RANGE 14
call :ASK_GRAIN_VAR
call :ASK_ENCODER
call :RUN_PRESET deband_fine_grain --range %DEBAND_RANGE% --grain-var %GRAIN_VAR%
goto MAIN

:FILMIC_REBUILD
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE filmic_rebuild
call :ASK_SIGMA 2.0
call :ASK_DEBAND_RANGE 14
call :ASK_ENCODER
call :RUN_PRESET filmic_rebuild --sigma %SIGMA% --deband-range %DEBAND_RANGE%
goto MAIN

:ARCHIVE_CLEAN
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE archive_clean
call :ASK_DENOISE_BUCKET
call :ASK_ENCODER
call :RUN_PRESET archive_clean --denoise %DENOISE_BUCKET%
goto MAIN

:PREGRADE_PREP
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE pregrade_prep
call :ASK_PREGRADE_STRENGTH
call :ASK_ENCODER
call :RUN_PRESET pregrade_prep --strength %STRENGTH%
goto MAIN


REM =====================================================================
REM Tools
REM =====================================================================

:LIST_ENCODERS
call :RUNPY "%CORE_DIR%\main.py" list-encoders
if not defined AUDION_NO_PAUSE pause
goto MAIN

:DOCTOR
call :RUNPY "%CORE_DIR%\doctor.py"
if not defined AUDION_NO_PAUSE pause
goto MAIN

:PROBE
set "SRC_PATH="
echo.
set /p SRC_PATH=Input file [press Enter to pick from input folder] :
if not defined SRC_PATH set "SRC_PATH=%BASE_DIR%\input"
call :RUNPY "%CORE_DIR%\main.py" probe --input "%SRC_PATH%"
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

:ASK_STRENGTH
set "STRENGTH="
echo.
echo Strength bucket:
echo   1 - light
echo   2 - medium  (default)
echo   3 - strong
set /p STRENGTH=Select [2] :
if not defined STRENGTH set "STRENGTH=medium"
if /I "%STRENGTH%"=="1" set "STRENGTH=light"
if /I "%STRENGTH%"=="2" set "STRENGTH=medium"
if /I "%STRENGTH%"=="3" set "STRENGTH=strong"
goto :eof

:ASK_PREGRADE_STRENGTH
set "STRENGTH="
echo.
echo Strength (pregrade is intentionally minimal):
echo   1 - light  (sigma=3.0)  default
echo   2 - medium (sigma=6.0)
set /p STRENGTH=Select [1] :
if not defined STRENGTH set "STRENGTH=light"
if /I "%STRENGTH%"=="1" set "STRENGTH=light"
if /I "%STRENGTH%"=="2" set "STRENGTH=medium"
goto :eof

:ASK_DENOISE_BUCKET
set "DENOISE_BUCKET="
echo.
echo Denoise bucket (DFTTest sigma):
echo   1 - light  (sigma=4)   default for archive
echo   2 - medium (sigma=8)
echo   3 - strong (sigma=14)
set /p DENOISE_BUCKET=Select [1] :
if not defined DENOISE_BUCKET set "DENOISE_BUCKET=light"
if /I "%DENOISE_BUCKET%"=="1" set "DENOISE_BUCKET=light"
if /I "%DENOISE_BUCKET%"=="2" set "DENOISE_BUCKET=medium"
if /I "%DENOISE_BUCKET%"=="3" set "DENOISE_BUCKET=strong"
goto :eof

:ASK_SIGMA
REM args: %1 = default value (e.g. 2.5)
set "SIGMA="
echo.
echo BM3D luma sigma (chroma is sigma*0.6):
echo   1 - 1.5   (light)
echo   2 - 2.0
echo   3 - 2.5   (medium / typical default)
echo   4 - 3.0
echo   5 - 3.5   (strong)
set /p SIGMA=Select or type number [%~1] :
if not defined SIGMA set "SIGMA=%~1"
if /I "%SIGMA%"=="1" set "SIGMA=1.5"
if /I "%SIGMA%"=="2" set "SIGMA=2.0"
if /I "%SIGMA%"=="3" set "SIGMA=2.5"
if /I "%SIGMA%"=="4" set "SIGMA=3.0"
if /I "%SIGMA%"=="5" set "SIGMA=3.5"
goto :eof

:ASK_GRAIN_BACK
set "GRAIN_BACK="
echo.
echo Micro-grain restoration after denoise (anti-plastic):
echo   1 - 0.0  (off)
echo   2 - 0.3  (subtle)
echo   3 - 0.6  (default)
echo   4 - 1.0  (visible)
set /p GRAIN_BACK=Select [3] :
if not defined GRAIN_BACK set "GRAIN_BACK=0.6"
if /I "%GRAIN_BACK%"=="1" set "GRAIN_BACK=0.0"
if /I "%GRAIN_BACK%"=="2" set "GRAIN_BACK=0.3"
if /I "%GRAIN_BACK%"=="3" set "GRAIN_BACK=0.6"
if /I "%GRAIN_BACK%"=="4" set "GRAIN_BACK=1.0"
goto :eof

:ASK_GRAIN_VAR
set "GRAIN_VAR="
echo.
echo AddGrain variance (for fine-grain restoration):
echo   1 - 0.3  (subtle)
echo   2 - 0.6  (default)
echo   3 - 1.0  (visible)
set /p GRAIN_VAR=Select [2] :
if not defined GRAIN_VAR set "GRAIN_VAR=0.6"
if /I "%GRAIN_VAR%"=="1" set "GRAIN_VAR=0.3"
if /I "%GRAIN_VAR%"=="2" set "GRAIN_VAR=0.6"
if /I "%GRAIN_VAR%"=="3" set "GRAIN_VAR=1.0"
goto :eof

:ASK_SHADOW_THRESHOLD
set "SHADOW_THRESHOLD="
echo.
echo Shadow threshold (luma cut, 0..1):
echo   1 - 0.10  (only deep shadows)
echo   2 - 0.20  (default -- shadows below 20%% luma)
echo   3 - 0.30  (extends into low-mids)
echo   4 - 0.40  (large region)
set /p SHADOW_THRESHOLD=Select [2] :
if not defined SHADOW_THRESHOLD set "SHADOW_THRESHOLD=0.20"
if /I "%SHADOW_THRESHOLD%"=="1" set "SHADOW_THRESHOLD=0.10"
if /I "%SHADOW_THRESHOLD%"=="2" set "SHADOW_THRESHOLD=0.20"
if /I "%SHADOW_THRESHOLD%"=="3" set "SHADOW_THRESHOLD=0.30"
if /I "%SHADOW_THRESHOLD%"=="4" set "SHADOW_THRESHOLD=0.40"
goto :eof

:ASK_DEBAND_RANGE
REM args: %1 = default
set "DEBAND_RANGE="
echo.
echo neo_f3kdb range (8..32, larger = stronger):
echo   1 - 10  (very gentle)
echo   2 - 12  (safe)
echo   3 - 14  (medium)
echo   4 - 16  (visible)
set /p DEBAND_RANGE=Select or type number [%~1] :
if not defined DEBAND_RANGE set "DEBAND_RANGE=%~1"
if /I "%DEBAND_RANGE%"=="1" set "DEBAND_RANGE=10"
if /I "%DEBAND_RANGE%"=="2" set "DEBAND_RANGE=12"
if /I "%DEBAND_RANGE%"=="3" set "DEBAND_RANGE=14"
if /I "%DEBAND_RANGE%"=="4" set "DEBAND_RANGE=16"
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
REM args: %1 = preset_name, %2.. = extra CLI flags
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
echo [run] precision/%PRESET%
echo       input:   %SRC_PATH%
echo       output:  %DST_PATH%
echo       encoder: %ENCODER%
echo.
call :RUNPY "%CORE_DIR%\main.py" run --palette precision --preset %PRESET% --input "%SRC_PATH%" --output "%DST_PATH%" --encoder %ENCODER%%EXTRA%
echo.
if not defined AUDION_NO_PAUSE pause
goto :eof


REM =====================================================================
REM Plumbing
REM =====================================================================

:NO_PYTHON
cls
echo [ERROR] Python orchestrator runtime was not resolved.
echo.
echo Expected: runtime\python.exe
echo Run builder_main.cmd -^> [01] BUILD PORTABLE ENV first.
echo.
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
