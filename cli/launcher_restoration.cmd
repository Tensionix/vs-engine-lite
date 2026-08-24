@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Restoration Engine (English)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\restoration_menu_en.txt"
set "RES_FILE=%RUNTIME_DIR%\restoration_menu_en_res.txt"

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
echo   AUDION VS ENGINE - RESTORATION  (deinterlace / IVTC / MC denoise)
echo ======================================================================
echo Root:      %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Menu mode: %MENU_MODE%
echo Tip:       these presets need extra plugins (havsfunc, mvtools, tivtc).
echo            Run builder_main.cmd -^> [12] INSTALL VS PLUGINS once.
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Field rebuild =================================================
>>"%MENU_FILE%" echo [01] QTGMC deinterlace          ^| qtgmc           ^| NNEDI3 + MVTools; gold-standard deinterlace
>>"%MENU_FILE%" echo [02] TIVTC inverse-telecine     ^| tivtc           ^| NTSC 29.97 telecined -^> 23.976 progressive
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Motion-compensated denoise ====================================
>>"%MENU_FILE%" echo [03] MVTools MCDeGrain          ^| mcdegrain       ^| temporal denoise that keeps detail (Topaz-style)
>>"%MENU_FILE%" echo [04] Derainbow / decross        ^| derainbow       ^| NTSC composite chroma cleanup (rainbow, dot crawl)
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Compression rescue ============================================
>>"%MENU_FILE%" echo [05] Deblock H.264 artefacts    ^| deblock         ^| over-compressed YouTube / WhatsApp / broadcast
>>"%MENU_FILE%" echo [06] Dehaze / local contrast    ^| dehaze          ^| clarity, no halos, no color shift
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Clean upscale =================================================
>>"%MENU_FILE%" echo [07] NNEDI3 2x upscale         ^| nnedi3_upscale  ^| deterministic non-ML enlargement for Lite
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Tools =========================================================
>>"%MENU_FILE%" echo [08] List encoders              ^| list_encoders   ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [09] Doctor                     ^| doctor          ^| full stack health
>>"%MENU_FILE%" echo [10] Open input folder          ^| open_input      ^| Explorer
>>"%MENU_FILE%" echo [11] Open output folder         ^| open_output     ^| Explorer
>>"%MENU_FILE%" echo [12] Open logs folder           ^| open_logs       ^| JSON reports
>>"%MENU_FILE%" echo [00] Back / Exit                ^| exit            ^| close

"%FZF_CMD%" --prompt="audion@restoration > " --pointer=">" --header="Restoration: legacy + compression rescue. Pick a preset." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="qtgmc"          goto QTGMC
if /I "%RAW%"=="tivtc"          goto TIVTC
if /I "%RAW%"=="mcdegrain"      goto MCDEGRAIN
if /I "%RAW%"=="derainbow"      goto DERAINBOW
if /I "%RAW%"=="deblock"        goto DEBLOCK
if /I "%RAW%"=="dehaze"         goto DEHAZE
if /I "%RAW%"=="nnedi3_upscale"  goto NNEDI3_UPSCALE
if /I "%RAW%"=="list_encoders"  goto LIST_ENCODERS
if /I "%RAW%"=="doctor"         goto DOCTOR
if /I "%RAW%"=="open_input"     goto OPEN_INPUT
if /I "%RAW%"=="open_output"    goto OPEN_OUTPUT
if /I "%RAW%"=="open_logs"      goto OPEN_LOGS
if /I "%RAW%"=="exit"           exit /b 0
goto MAIN

:FALLBACK_MENU
echo === Field rebuild ===
echo [1] QTGMC deinterlace        (NNEDI3 + MVTools)
echo [2] TIVTC inverse-telecine   (NTSC 29.97 -^> 23.976)
echo === Motion-compensated denoise ===
echo [3] MVTools MCDeGrain        (Topaz-style, keeps detail)
echo [4] Derainbow / decross      (NTSC composite chroma)
echo === Compression rescue ===
echo [5] Deblock H.264 artefacts  (YouTube / WhatsApp / SD broadcast)
echo [6] Dehaze / local contrast  (no halos, no color shift)
echo === Clean upscale ===
echo [7] NNEDI3 2x upscale        (deterministic non-ML enlargement)
echo.
echo === Tools ===
echo [8] List encoders
echo [9] Doctor
echo [A] Open input folder
echo [B] Open output folder
echo [C] Open logs folder
echo [0] Back / Exit
echo.
choice /C 123456789ABC0 /N /M "Select: "
if errorlevel 13 exit /b 0
if errorlevel 12 goto OPEN_LOGS
if errorlevel 11 goto OPEN_OUTPUT
if errorlevel 10 goto OPEN_INPUT
if errorlevel 9  goto DOCTOR
if errorlevel 8  goto LIST_ENCODERS
if errorlevel 7  goto NNEDI3_UPSCALE
if errorlevel 6  goto DEHAZE
if errorlevel 5  goto DEBLOCK
if errorlevel 4  goto DERAINBOW
if errorlevel 3  goto MCDEGRAIN
if errorlevel 2  goto TIVTC
if errorlevel 1  goto QTGMC
goto MAIN


REM =====================================================================
REM Preset actions
REM =====================================================================

:QTGMC
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE qtgmc
call :ASK_FIELD_ORDER
call :ASK_QTGMC_PRESET
call :ASK_OUTPUT_FPS
call :ASK_ENCODER
call :RUN_PRESET qtgmc_deinterlace --field-order %FIELD_ORDER% --qtgmc-preset "%QPRESET%" --output-fps %OUTPUT_FPS%
goto MAIN

:TIVTC
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE tivtc
call :ASK_ENCODER
call :RUN_PRESET tivtc_ivtc
goto MAIN

:MCDEGRAIN
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE mcdegrain
call :ASK_RADIUS_3
call :ASK_THSAD
call :ASK_BLKSIZE
call :ASK_ENCODER
call :RUN_PRESET mvtools_mcdegrain --radius %RADIUS% --thsad %THSAD% --blksize %BLKSIZE%
goto MAIN

:DERAINBOW
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE derainbow
call :ASK_DERAINBOW_STRENGTH
call :ASK_BLKSIZE
call :ASK_ENCODER
call :RUN_PRESET derainbow_decross --strength %STRENGTH% --blksize %BLKSIZE%
goto MAIN

:DEBLOCK
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE deblock
call :ASK_DEBLOCK_QUANT
call :ASK_ENCODER
call :RUN_PRESET deblock_h264_artefacts --quant1 %QUANT1% --quant2 %QUANT2%
goto MAIN

:DEHAZE
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE dehaze
call :ASK_DEHAZE_STRENGTH
call :ASK_DEHAZE_RADIUS
call :ASK_ENCODER
call :RUN_PRESET dehaze_local_contrast --strength %STRENGTH% --radius %RADIUS%
goto MAIN

:NNEDI3_UPSCALE
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE nnedi3_2x
call :ASK_NNEDI3_QUALITY
call :ASK_NNEDI3_CHROMA
call :ASK_ENCODER
call :RUN_PRESET nnedi3_upscale_2x --quality %QUALITY% --chroma %CHROMA%
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

:ASK_FIELD_ORDER
set "FIELD_ORDER="
echo.
echo Field order:
echo   1 - tff  (top-field-first; broadcast / HDV / DV-NTSC)
echo   2 - bff  (bottom-field-first; DV-PAL)
set /p FIELD_ORDER=Select [1] :
if not defined FIELD_ORDER set "FIELD_ORDER=tff"
if /I "%FIELD_ORDER%"=="1" set "FIELD_ORDER=tff"
if /I "%FIELD_ORDER%"=="2" set "FIELD_ORDER=bff"
goto :eof

:ASK_QTGMC_PRESET
set "QPRESET="
echo.
echo QTGMC speed/quality preset:
echo   1 - Faster      (good for previews)
echo   2 - Fast
echo   3 - Medium      (default)
echo   4 - Slow
echo   5 - Slower
echo   6 - Placebo     (slowest, sharpest)
set /p QPRESET=Select [3] :
if not defined QPRESET set "QPRESET=Medium"
if /I "%QPRESET%"=="1" set "QPRESET=Faster"
if /I "%QPRESET%"=="2" set "QPRESET=Fast"
if /I "%QPRESET%"=="3" set "QPRESET=Medium"
if /I "%QPRESET%"=="4" set "QPRESET=Slow"
if /I "%QPRESET%"=="5" set "QPRESET=Slower"
if /I "%QPRESET%"=="6" set "QPRESET=Placebo"
goto :eof

:ASK_OUTPUT_FPS
set "OUTPUT_FPS="
echo.
echo Output frame rate:
echo   1 - single  (input fps; one progressive per source frame)
echo   2 - double  (2x fps; smoothest motion, doubles encode time)
set /p OUTPUT_FPS=Select [1] :
if not defined OUTPUT_FPS set "OUTPUT_FPS=single"
if /I "%OUTPUT_FPS%"=="1" set "OUTPUT_FPS=single"
if /I "%OUTPUT_FPS%"=="2" set "OUTPUT_FPS=double"
goto :eof

:ASK_RADIUS_3
set "RADIUS="
echo.
echo Temporal radius (frames before/after considered):
echo   1 - 1   (light, 3-frame window)
echo   2 - 2   (default, 5-frame window)
echo   3 - 3   (heavy, 7-frame window)
set /p RADIUS=Select [2] :
if not defined RADIUS set "RADIUS=2"
goto :eof

:ASK_THSAD
set "THSAD="
echo.
echo Block-match SAD threshold:
echo   1 - 100   (only confident matches; gentle denoise)
echo   2 - 200   (default, balanced)
echo   3 - 300   (more averaging; stronger denoise)
echo   4 - 400   (max; risk of motion smear)
set /p THSAD=Select [2] :
if not defined THSAD set "THSAD=200"
if /I "%THSAD%"=="1" set "THSAD=100"
if /I "%THSAD%"=="2" set "THSAD=200"
if /I "%THSAD%"=="3" set "THSAD=300"
if /I "%THSAD%"=="4" set "THSAD=400"
goto :eof

:ASK_BLKSIZE
set "BLKSIZE="
echo.
echo Motion search block size:
echo   1 - 16  (default, faster, good for HD)
echo   2 - 8   (slower, better fine detail at 4K)
set /p BLKSIZE=Select [1] :
if not defined BLKSIZE set "BLKSIZE=16"
if /I "%BLKSIZE%"=="1" set "BLKSIZE=16"
if /I "%BLKSIZE%"=="2" set "BLKSIZE=8"
goto :eof

:ASK_DERAINBOW_STRENGTH
set "STRENGTH="
echo.
echo Chroma smoothing strength:
echo   1 - 0.3   (subtle)
echo   2 - 0.6   (default)
echo   3 - 1.0   (max)
set /p STRENGTH=Select [2] :
if not defined STRENGTH set "STRENGTH=0.6"
if /I "%STRENGTH%"=="1" set "STRENGTH=0.3"
if /I "%STRENGTH%"=="2" set "STRENGTH=0.6"
if /I "%STRENGTH%"=="3" set "STRENGTH=1.0"
goto :eof

:ASK_DEBLOCK_QUANT
set "QUANT1="
set "QUANT2="
echo.
echo Deblock strength:
echo   1 - light    (quant1=20, quant2=22)
echo   2 - default  (quant1=24, quant2=26)
echo   3 - heavy    (quant1=28, quant2=30)
set /p Q=Select [2] :
if not defined Q set "Q=2"
if /I "%Q%"=="1" ( set "QUANT1=20" & set "QUANT2=22" )
if /I "%Q%"=="2" ( set "QUANT1=24" & set "QUANT2=26" )
if /I "%Q%"=="3" ( set "QUANT1=28" & set "QUANT2=30" )
goto :eof

:ASK_DEHAZE_STRENGTH
set "STRENGTH="
echo.
echo Local contrast strength:
echo   1 - 0.5   (subtle clarity)
echo   2 - 1.0   (default, balanced)
echo   3 - 1.5   (strong)
echo   4 - 2.0   (aggressive)
set /p STRENGTH=Select [2] :
if not defined STRENGTH set "STRENGTH=1.0"
if /I "%STRENGTH%"=="1" set "STRENGTH=0.5"
if /I "%STRENGTH%"=="2" set "STRENGTH=1.0"
if /I "%STRENGTH%"=="3" set "STRENGTH=1.5"
if /I "%STRENGTH%"=="4" set "STRENGTH=2.0"
goto :eof

:ASK_DEHAZE_RADIUS
set "RADIUS="
echo.
echo Low-pass radius (in pixels):
echo   1 - 4    (fine clarity)
echo   2 - 8    (default, balanced)
echo   3 - 12   (haze removal)
echo   4 - 16   (strong haze)
set /p RADIUS=Select [2] :
if not defined RADIUS set "RADIUS=8"
if /I "%RADIUS%"=="1" set "RADIUS=4"
if /I "%RADIUS%"=="2" set "RADIUS=8"
if /I "%RADIUS%"=="3" set "RADIUS=12"
if /I "%RADIUS%"=="4" set "RADIUS=16"
goto :eof

:ASK_NNEDI3_QUALITY
set "QUALITY="
echo.
echo NNEDI3 quality / speed:
echo   1 - fast      (lighter)
echo   2 - balanced  (default)
echo   3 - best      (slower, cleaner edges)
set /p QUALITY=Select [2] :
if not defined QUALITY set "QUALITY=balanced"
if /I "%QUALITY%"=="1" set "QUALITY=fast"
if /I "%QUALITY%"=="2" set "QUALITY=balanced"
if /I "%QUALITY%"=="3" set "QUALITY=best"
goto :eof

:ASK_NNEDI3_CHROMA
set "CHROMA="
echo.
echo Chroma upscale:
echo   1 - spline36  (default, safe)
echo   2 - nnedi3    (sharper, slower)
set /p CHROMA=Select [1] :
if not defined CHROMA set "CHROMA=spline36"
if /I "%CHROMA%"=="1" set "CHROMA=spline36"
if /I "%CHROMA%"=="2" set "CHROMA=nnedi3"
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
echo [run] restoration/%PRESET%
echo       input:   %SRC_PATH%
echo       output:  %DST_PATH%
echo       encoder: %ENCODER%
echo.
call :RUNPY "%CORE_DIR%\main.py" run --palette restoration --preset %PRESET% --input "%SRC_PATH%" --output "%DST_PATH%" --encoder %ENCODER%%EXTRA%
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
