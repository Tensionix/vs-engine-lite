@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Precision Engine (Русский)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\precision_menu_ru.txt"
set "RES_FILE=%RUNTIME_DIR%\precision_menu_ru_res.txt"

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
echo   AUDION VS ENGINE - PRECISION  (шумодав / дебанд / зерно)
echo ======================================================================
echo Корень:    %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Меню:      %MENU_MODE%
echo Пайплайн:  Шаг 1 Шумодав -^> Шаг 2 Дебанд -^> Шаг 3 Композиции
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Шаг 1 -- Шумодав (сначала чистим) =============================
>>"%MENU_FILE%" echo [01] Мягкий шумодав                 ^| mild_denoise         ^| DFTTest, универсальный, лёгкий/средний/сильный
>>"%MENU_FILE%" echo [02] Шумодав теней SOTA — *флагман* ^| shadow_denoise_sota  ^| BM3D только в зоне теней (CUDA-^>CPU)
>>"%MENU_FILE%" echo [03] Очистка хромы                  ^| chroma_cleanup       ^| DFTTest только на хрома-плоскостях
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Шаг 2 -- Дебанд (сглаживаем градиенты) ========================
>>"%MENU_FILE%" echo [04] Дебанд безопасный              ^| deband_safe          ^| neo_f3kdb лёгкий, без зерна
>>"%MENU_FILE%" echo [05] Дебанд + тонкое зерно          ^| deband_fine_grain    ^| neo_f3kdb + AddGrain возврат фактуры
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Шаг 3 -- Композиции (полные цепочки) ==========================
>>"%MENU_FILE%" echo [06] Filmic Rebuild — *флагман*     ^| filmic_rebuild       ^| шумодав -^> дебанд -^> зерно по зонам яркости
>>"%MENU_FILE%" echo [07] Архивная очистка               ^| archive_clean        ^| нейтральный мастер, без зерна
>>"%MENU_FILE%" echo [08] Пре-грейд подготовка           ^| pregrade_prep        ^| минимум воздействия для Resolve
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Сервис ========================================================
>>"%MENU_FILE%" echo [09] Список энкодеров               ^| list_encoders        ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [10] Доктор (полная диагностика)    ^| doctor               ^| VS / плагины / FFmpeg / CUDA
>>"%MENU_FILE%" echo [11] Анализ файла                   ^| probe                ^| ffprobe summary (JSON)
>>"%MENU_FILE%" echo [12] Открыть папку input            ^| open_input           ^| Explorer
>>"%MENU_FILE%" echo [13] Открыть папку output           ^| open_output          ^| Explorer
>>"%MENU_FILE%" echo [14] Открыть папку logs             ^| open_logs            ^| JSON отчёты
>>"%MENU_FILE%" echo [00] Назад / Выход                  ^| exit                 ^| закрыть

"%FZF_CMD%" --prompt="audion@precision-ru > " --pointer=">" --header="Шаг 1 (шумодав) -> Шаг 2 (дебанд) -> Шаг 3 (композиции). Выберите действие." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

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
echo === ШАГ 1 -- ШУМОДАВ ===
echo [1] Мягкий шумодав             (DFTTest универсальный)
echo [2] Шумодав теней SOTA  *      (BM3D + маска теней)
echo [3] Очистка хромы              (DFTTest только хрома)
echo.
echo === ШАГ 2 -- ДЕБАНД ===
echo [4] Дебанд безопасный          (neo_f3kdb лёгкий)
echo [5] Дебанд + тонкое зерно      (neo_f3kdb + AddGrain)
echo.
echo === ШАГ 3 -- КОМПОЗИЦИИ ===
echo [6] Filmic Rebuild       *     (шумодав -^> дебанд -^> зерно по зонам)
echo [7] Архивная очистка           (нейтральный мастер)
echo [8] Пре-грейд подготовка       (для Resolve)
echo.
echo === СЕРВИС ===
echo [9] Список энкодеров
echo [A] Доктор
echo [B] Анализ файла
echo [C] Открыть папку input
echo [D] Открыть папку output
echo [E] Открыть папку logs
echo [0] Назад / Выход
echo.
choice /C 123456789ABCDE0 /N /M "Выбор: "
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
REM Действия пресетов
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
REM Сервис
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
set /p SRC_PATH=Файл для анализа [Enter -- взять из папки input] :
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
REM Параметры (UI prompts)
REM =====================================================================

:ASK_INPUT_FILE
set "SRC_PATH="
echo.
echo [INFO] Нажмите Enter для папки input проекта или укажите путь к файлу/папке.
set /p SRC_PATH=Файл или папка input [input] :
if not defined SRC_PATH set "SRC_PATH=%BASE_DIR%\input"
goto :eof

:ASK_OUTPUT_FILE
set "DST_PATH="
echo.
set /p DST_PATH=Выходной файл [output\out_%~1.mp4] :
if not defined DST_PATH set "DST_PATH=%BASE_DIR%\output\out_%~1.mp4"
goto :eof

:ASK_STRENGTH
set "STRENGTH="
echo.
echo Сила воздействия:
echo   1 - light    (лёгкая)
echo   2 - medium   (средняя, по умолчанию)
echo   3 - strong   (сильная)
set /p STRENGTH=Выбор [2] :
if not defined STRENGTH set "STRENGTH=medium"
if /I "%STRENGTH%"=="1" set "STRENGTH=light"
if /I "%STRENGTH%"=="2" set "STRENGTH=medium"
if /I "%STRENGTH%"=="3" set "STRENGTH=strong"
goto :eof

:ASK_PREGRADE_STRENGTH
set "STRENGTH="
echo.
echo Сила (пре-грейд намеренно минимален):
echo   1 - light  (sigma=3.0)  по умолчанию
echo   2 - medium (sigma=6.0)
set /p STRENGTH=Выбор [1] :
if not defined STRENGTH set "STRENGTH=light"
if /I "%STRENGTH%"=="1" set "STRENGTH=light"
if /I "%STRENGTH%"=="2" set "STRENGTH=medium"
goto :eof

:ASK_DENOISE_BUCKET
set "DENOISE_BUCKET="
echo.
echo Уровень шумодава (DFTTest sigma):
echo   1 - light  (sigma=4)   по умолчанию для архива
echo   2 - medium (sigma=8)
echo   3 - strong (sigma=14)
set /p DENOISE_BUCKET=Выбор [1] :
if not defined DENOISE_BUCKET set "DENOISE_BUCKET=light"
if /I "%DENOISE_BUCKET%"=="1" set "DENOISE_BUCKET=light"
if /I "%DENOISE_BUCKET%"=="2" set "DENOISE_BUCKET=medium"
if /I "%DENOISE_BUCKET%"=="3" set "DENOISE_BUCKET=strong"
goto :eof

:ASK_SIGMA
set "SIGMA="
echo.
echo BM3D sigma на luma (на хрома будет sigma*0.6):
echo   1 - 1.5   (лёгкая)
echo   2 - 2.0
echo   3 - 2.5   (средняя / типовое значение)
echo   4 - 3.0
echo   5 - 3.5   (сильная)
set /p SIGMA=Выбор или число [%~1] :
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
echo Возврат микрозерна после шумодава (анти-пластик):
echo   1 - 0.0  (выкл)
echo   2 - 0.3  (едва заметно)
echo   3 - 0.6  (по умолчанию)
echo   4 - 1.0  (заметно)
set /p GRAIN_BACK=Выбор [3] :
if not defined GRAIN_BACK set "GRAIN_BACK=0.6"
if /I "%GRAIN_BACK%"=="1" set "GRAIN_BACK=0.0"
if /I "%GRAIN_BACK%"=="2" set "GRAIN_BACK=0.3"
if /I "%GRAIN_BACK%"=="3" set "GRAIN_BACK=0.6"
if /I "%GRAIN_BACK%"=="4" set "GRAIN_BACK=1.0"
goto :eof

:ASK_GRAIN_VAR
set "GRAIN_VAR="
echo.
echo AddGrain дисперсия (для возврата тонкой текстуры):
echo   1 - 0.3  (едва заметно)
echo   2 - 0.6  (по умолчанию)
echo   3 - 1.0  (заметно)
set /p GRAIN_VAR=Выбор [2] :
if not defined GRAIN_VAR set "GRAIN_VAR=0.6"
if /I "%GRAIN_VAR%"=="1" set "GRAIN_VAR=0.3"
if /I "%GRAIN_VAR%"=="2" set "GRAIN_VAR=0.6"
if /I "%GRAIN_VAR%"=="3" set "GRAIN_VAR=1.0"
goto :eof

:ASK_SHADOW_THRESHOLD
set "SHADOW_THRESHOLD="
echo.
echo Порог теней (luma cut, 0..1):
echo   1 - 0.10  (только глубокие тени)
echo   2 - 0.20  (по умолчанию -- тени ниже 20%% яркости)
echo   3 - 0.30  (захватывает нижние полутона)
echo   4 - 0.40  (большая зона)
set /p SHADOW_THRESHOLD=Выбор [2] :
if not defined SHADOW_THRESHOLD set "SHADOW_THRESHOLD=0.20"
if /I "%SHADOW_THRESHOLD%"=="1" set "SHADOW_THRESHOLD=0.10"
if /I "%SHADOW_THRESHOLD%"=="2" set "SHADOW_THRESHOLD=0.20"
if /I "%SHADOW_THRESHOLD%"=="3" set "SHADOW_THRESHOLD=0.30"
if /I "%SHADOW_THRESHOLD%"=="4" set "SHADOW_THRESHOLD=0.40"
goto :eof

:ASK_DEBAND_RANGE
set "DEBAND_RANGE="
echo.
echo neo_f3kdb range (8..32, больше = сильнее):
echo   1 - 10  (очень мягкий)
echo   2 - 12  (безопасный)
echo   3 - 14  (средний)
echo   4 - 16  (заметный)
set /p DEBAND_RANGE=Выбор или число [%~1] :
if not defined DEBAND_RANGE set "DEBAND_RANGE=%~1"
if /I "%DEBAND_RANGE%"=="1" set "DEBAND_RANGE=10"
if /I "%DEBAND_RANGE%"=="2" set "DEBAND_RANGE=12"
if /I "%DEBAND_RANGE%"=="3" set "DEBAND_RANGE=14"
if /I "%DEBAND_RANGE%"=="4" set "DEBAND_RANGE=16"
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
REM Запуск пресета
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
echo [запуск] precision/%PRESET%
echo          вход:    %SRC_PATH%
echo          выход:   %DST_PATH%
echo          энкодер: %ENCODER%
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
echo [ОШИБКА] Python оркестратора не найден.
echo.
echo Ожидается: runtime\python.exe
echo Запустите builder_main.cmd -^> [01] BUILD PORTABLE ENV
echo.
if not defined AUDION_NO_PAUSE pause
exit /b 1

:RUNPY
set "TARGET=%~1"
if not exist "%TARGET%" (
  echo [ОШИБКА] Скрипт не найден:
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
