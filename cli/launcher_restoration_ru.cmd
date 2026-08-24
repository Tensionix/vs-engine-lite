@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Палитра Restoration (русский)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\restoration_menu_ru.txt"
set "RES_FILE=%RUNTIME_DIR%\restoration_menu_ru_res.txt"

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
echo   AUDION VS ENGINE - RESTORATION  (деинтерлейс / IVTC / MC denoise)
echo ======================================================================
echo Корень:     %BASE_DIR%
echo Python:     %PYTHON_CMD% %PYTHON_ARGS%
echo Меню:       %MENU_MODE%
echo Подсказка:  пресетам нужны плагины havsfunc / mvtools / tivtc.
echo             Запустите builder_main.cmd -^> [12] INSTALL VS PLUGINS один раз.
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Восстановление полей ==========================================
>>"%MENU_FILE%" echo [01] QTGMC деинтерлейс           ^| qtgmc           ^| NNEDI3 + MVTools; эталонный деинтерлейс
>>"%MENU_FILE%" echo [02] TIVTC обратный telecine     ^| tivtc           ^| NTSC 29.97 -^> 23.976 progressive
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === MC-шумодав (motion-compensated) ===============================
>>"%MENU_FILE%" echo [03] MVTools MCDeGrain           ^| mcdegrain       ^| temporal denoise без потери детализации
>>"%MENU_FILE%" echo [04] Derainbow / decross         ^| derainbow       ^| NTSC composite (радуга, dot crawl)
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Спасение пережатого ===========================================
>>"%MENU_FILE%" echo [05] Deblock H.264               ^| deblock         ^| YouTube / WhatsApp / SD broadcast
>>"%MENU_FILE%" echo [06] Dehaze / локальный контраст ^| dehaze          ^| без halos и color shift
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Чистый апскейл ================================================
>>"%MENU_FILE%" echo [07] NNEDI3 2x upscale           ^| nnedi3_upscale  ^| non-ML увеличение для Lite
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Сервис ========================================================
>>"%MENU_FILE%" echo [08] Список энкодеров            ^| list_encoders   ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [09] Доктор                      ^| doctor          ^| диагностика стека
>>"%MENU_FILE%" echo [10] Открыть папку input         ^| open_input      ^| Explorer
>>"%MENU_FILE%" echo [11] Открыть папку output        ^| open_output     ^| Explorer
>>"%MENU_FILE%" echo [12] Открыть папку logs          ^| open_logs       ^| JSON отчёты
>>"%MENU_FILE%" echo [00] Назад / Выход               ^| exit            ^| закрыть

"%FZF_CMD%" --prompt="audion@restoration-ru > " --pointer=">" --header="Restoration: legacy + спасение пережатого. Выберите пресет." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

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
echo === Восстановление полей ===
echo [1] QTGMC деинтерлейс         (NNEDI3 + MVTools)
echo [2] TIVTC обратный telecine   (NTSC 29.97 -^> 23.976)
echo === MC-шумодав ===
echo [3] MVTools MCDeGrain         (без потери детализации)
echo [4] Derainbow / decross       (NTSC composite chroma)
echo === Спасение пережатого ===
echo [5] Deblock H.264             (YouTube / WhatsApp / SD broadcast)
echo [6] Dehaze / локальный контраст
echo === Чистый апскейл ===
echo [7] NNEDI3 2x upscale         (non-ML увеличение для Lite)
echo.
echo === Сервис ===
echo [8] Список энкодеров
echo [9] Доктор
echo [A] Открыть папку input
echo [B] Открыть папку output
echo [C] Открыть папку logs
echo [0] Назад / Выход
echo.
choice /C 123456789ABC0 /N /M "Выбор: "
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
REM Действия пресетов
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
REM Параметры
REM =====================================================================

:ASK_INPUT_FILE
set "SRC_PATH="
echo.
echo [INFO] Enter = взять папку input, либо вставьте путь к файлу/папке.
set /p SRC_PATH=Файл или папка [input] :
if not defined SRC_PATH set "SRC_PATH=%BASE_DIR%\input"
goto :eof

:ASK_OUTPUT_FILE
set "DST_PATH="
echo.
set /p DST_PATH=Файл сохранения [output\out_%~1.mp4] :
if not defined DST_PATH set "DST_PATH=%BASE_DIR%\output\out_%~1.mp4"
goto :eof

:ASK_FIELD_ORDER
set "FIELD_ORDER="
echo.
echo Порядок полей:
echo   1 - tff  (top-field-first; broadcast / HDV / DV-NTSC)
echo   2 - bff  (bottom-field-first; DV-PAL)
set /p FIELD_ORDER=Выбор [1] :
if not defined FIELD_ORDER set "FIELD_ORDER=tff"
if /I "%FIELD_ORDER%"=="1" set "FIELD_ORDER=tff"
if /I "%FIELD_ORDER%"=="2" set "FIELD_ORDER=bff"
goto :eof

:ASK_QTGMC_PRESET
set "QPRESET="
echo.
echo Скорость / качество QTGMC:
echo   1 - Faster      (для превью)
echo   2 - Fast
echo   3 - Medium      (по умолчанию)
echo   4 - Slow
echo   5 - Slower
echo   6 - Placebo     (медленнее всего, резче всего)
set /p QPRESET=Выбор [3] :
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
echo Выходной фреймрейт:
echo   1 - single  (как в источнике; 1 progressive на каждый кадр)
echo   2 - double  (2x fps; самое плавное движение, +100%% времени)
set /p OUTPUT_FPS=Выбор [1] :
if not defined OUTPUT_FPS set "OUTPUT_FPS=single"
if /I "%OUTPUT_FPS%"=="1" set "OUTPUT_FPS=single"
if /I "%OUTPUT_FPS%"=="2" set "OUTPUT_FPS=double"
goto :eof

:ASK_RADIUS_3
set "RADIUS="
echo.
echo Временной радиус (кадров до и после):
echo   1 - 1   (лёгкий, окно 3 кадра)
echo   2 - 2   (по умолчанию, окно 5 кадров)
echo   3 - 3   (тяжёлый, окно 7 кадров)
set /p RADIUS=Выбор [2] :
if not defined RADIUS set "RADIUS=2"
goto :eof

:ASK_THSAD
set "THSAD="
echo.
echo Порог совпадения блоков (THSAD):
echo   1 - 100   (только уверенные совпадения; мягкий шумодав)
echo   2 - 200   (по умолчанию)
echo   3 - 300   (больше усреднения; сильный шумодав)
echo   4 - 400   (максимум; риск смазывания движения)
set /p THSAD=Выбор [2] :
if not defined THSAD set "THSAD=200"
if /I "%THSAD%"=="1" set "THSAD=100"
if /I "%THSAD%"=="2" set "THSAD=200"
if /I "%THSAD%"=="3" set "THSAD=300"
if /I "%THSAD%"=="4" set "THSAD=400"
goto :eof

:ASK_BLKSIZE
set "BLKSIZE="
echo.
echo Размер блока motion-search:
echo   1 - 16  (по умолчанию, быстрее, для HD)
echo   2 - 8   (медленнее, мелкие детали 4K)
set /p BLKSIZE=Выбор [1] :
if not defined BLKSIZE set "BLKSIZE=16"
if /I "%BLKSIZE%"=="1" set "BLKSIZE=16"
if /I "%BLKSIZE%"=="2" set "BLKSIZE=8"
goto :eof

:ASK_DERAINBOW_STRENGTH
set "STRENGTH="
echo.
echo Сила chroma smoothing:
echo   1 - 0.3   (тонко)
echo   2 - 0.6   (по умолчанию)
echo   3 - 1.0   (максимум)
set /p STRENGTH=Выбор [2] :
if not defined STRENGTH set "STRENGTH=0.6"
if /I "%STRENGTH%"=="1" set "STRENGTH=0.3"
if /I "%STRENGTH%"=="2" set "STRENGTH=0.6"
if /I "%STRENGTH%"=="3" set "STRENGTH=1.0"
goto :eof

:ASK_DEBLOCK_QUANT
set "QUANT1="
set "QUANT2="
echo.
echo Сила deblock:
echo   1 - light    (quant1=20, quant2=22)
echo   2 - default  (quant1=24, quant2=26)
echo   3 - heavy    (quant1=28, quant2=30)
set /p Q=Выбор [2] :
if not defined Q set "Q=2"
if /I "%Q%"=="1" ( set "QUANT1=20" & set "QUANT2=22" )
if /I "%Q%"=="2" ( set "QUANT1=24" & set "QUANT2=26" )
if /I "%Q%"=="3" ( set "QUANT1=28" & set "QUANT2=30" )
goto :eof

:ASK_DEHAZE_STRENGTH
set "STRENGTH="
echo.
echo Сила локального контраста:
echo   1 - 0.5   (тонкая чёткость)
echo   2 - 1.0   (по умолчанию)
echo   3 - 1.5   (сильно)
echo   4 - 2.0   (агрессивно)
set /p STRENGTH=Выбор [2] :
if not defined STRENGTH set "STRENGTH=1.0"
if /I "%STRENGTH%"=="1" set "STRENGTH=0.5"
if /I "%STRENGTH%"=="2" set "STRENGTH=1.0"
if /I "%STRENGTH%"=="3" set "STRENGTH=1.5"
if /I "%STRENGTH%"=="4" set "STRENGTH=2.0"
goto :eof

:ASK_DEHAZE_RADIUS
set "RADIUS="
echo.
echo Радиус low-pass (в пикселях):
echo   1 - 4    (тонкая чёткость)
echo   2 - 8    (по умолчанию)
echo   3 - 12   (удаление дымки)
echo   4 - 16   (сильная дымка)
set /p RADIUS=Выбор [2] :
if not defined RADIUS set "RADIUS=8"
if /I "%RADIUS%"=="1" set "RADIUS=4"
if /I "%RADIUS%"=="2" set "RADIUS=8"
if /I "%RADIUS%"=="3" set "RADIUS=12"
if /I "%RADIUS%"=="4" set "RADIUS=16"
goto :eof

:ASK_NNEDI3_QUALITY
set "QUALITY="
echo.
echo Качество / скорость NNEDI3:
echo   1 - fast      (быстрее)
echo   2 - balanced  (по умолчанию)
echo   3 - best      (медленнее, чище края)
set /p QUALITY=Выбор [2] :
if not defined QUALITY set "QUALITY=balanced"
if /I "%QUALITY%"=="1" set "QUALITY=fast"
if /I "%QUALITY%"=="2" set "QUALITY=balanced"
if /I "%QUALITY%"=="3" set "QUALITY=best"
goto :eof

:ASK_NNEDI3_CHROMA
set "CHROMA="
echo.
echo Апскейл chroma:
echo   1 - spline36  (по умолчанию, безопасно)
echo   2 - nnedi3    (резче, медленнее)
set /p CHROMA=Выбор [1] :
if not defined CHROMA set "CHROMA=spline36"
if /I "%CHROMA%"=="1" set "CHROMA=spline36"
if /I "%CHROMA%"=="2" set "CHROMA=nnedi3"
goto :eof

:ASK_ENCODER
set "ENCODER="
echo.
echo Профиль энкодера:
echo   1 - h264_crf14       (по умолчанию; semi-lossless, архивное качество)
echo   2 - h264_crf17       (почти невидимый lossy, Audion tier)
echo   3 - h264_crf21       (web / proxy / превью)
echo   4 - h265_crf17       (HEVC, меньше размер при том же качестве)
echo   5 - prores_lt        (ProRes по умолчанию; для DaVinci / round-trip)
echo   6 - prores_lt_mxf    (ProRes LT в MXF wrapper для Adobe / Avid)
echo   7 - h264_nvenc_q14   (NVIDIA hardware encode; разгружает CPU)
echo   8 - h265_nvenc_q17   (NVIDIA hardware HEVC; 10-bit p010le)
set /p ENCODER=Выбор [1] :
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
REM Запуск
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
echo       вход:    %SRC_PATH%
echo       выход:   %DST_PATH%
echo       энкодер: %ENCODER%
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
echo [ERROR] Python orchestrator runtime не найден.
echo Ожидался: runtime\python.exe
echo Запустите builder_main.cmd -^> [01] BUILD PORTABLE ENV.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:RUNPY
set "TARGET=%~1"
if not exist "%TARGET%" (
  echo [ERROR] Python script не найден:
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
