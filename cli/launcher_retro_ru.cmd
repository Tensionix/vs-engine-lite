@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine - Retro Engine (Русский)

for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\retro_menu_ru.txt"
set "RES_FILE=%RUNTIME_DIR%\retro_menu_ru_res.txt"

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
echo   AUDION VS ENGINE - RETRO  (VHS / CRT / camcorder)
echo ======================================================================
echo Корень:    %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Меню:      %MENU_MODE%
echo Подсказка: intensity 0.0 = выкл, 1.0 = настроено, 2.0 = сильно
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Ретро-эстетика (аналоговый характер) ==========================
>>"%MENU_FILE%" echo [01] VHS / CRT                             ^| vhs_crt         ^| chroma bleed, мягкая оптика, аналоговый шум
>>"%MENU_FILE%" echo [02] Camcorder 90s                         ^| camcorder_90s   ^| мягче VHS, лёгкая переэкспозиция
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Сервис ========================================================
>>"%MENU_FILE%" echo [03] Список энкодеров                      ^| list_encoders   ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [04] Доктор                                ^| doctor          ^| диагностика стека
>>"%MENU_FILE%" echo [05] Открыть папку input                   ^| open_input      ^| Explorer
>>"%MENU_FILE%" echo [06] Открыть папку output                  ^| open_output     ^| Explorer
>>"%MENU_FILE%" echo [07] Открыть папку logs                    ^| open_logs       ^| JSON отчёты
>>"%MENU_FILE%" echo [00] Назад / Выход                         ^| exit            ^| закрыть

"%FZF_CMD%" --prompt="audion@retro-ru > " --pointer=">" --header="Аналоговая стилизация. Выберите пресет." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="vhs_crt"        goto VHS_CRT
if /I "%RAW%"=="camcorder_90s"  goto CAMCORDER_90S
if /I "%RAW%"=="list_encoders"  goto LIST_ENCODERS
if /I "%RAW%"=="doctor"         goto DOCTOR
if /I "%RAW%"=="open_input"     goto OPEN_INPUT
if /I "%RAW%"=="open_output"    goto OPEN_OUTPUT
if /I "%RAW%"=="open_logs"      goto OPEN_LOGS
if /I "%RAW%"=="exit"           exit /b 0
goto MAIN

:FALLBACK_MENU
echo === Ретро-эстетика ===
echo [1] VHS / CRT             (chroma bleed, мягкая оптика)
echo [2] Camcorder 90s         (мягче VHS, переэкспозиция)
echo.
echo === Сервис ===
echo [3] Список энкодеров
echo [4] Доктор
echo [5] Открыть папку input
echo [6] Открыть папку output
echo [7] Открыть папку logs
echo [0] Назад / Выход
echo.
choice /C 12345670 /N /M "Выбор: "
if errorlevel 8 exit /b 0
if errorlevel 7 goto OPEN_LOGS
if errorlevel 6 goto OPEN_OUTPUT
if errorlevel 5 goto OPEN_INPUT
if errorlevel 4 goto DOCTOR
if errorlevel 3 goto LIST_ENCODERS
if errorlevel 2 goto CAMCORDER_90S
if errorlevel 1 goto VHS_CRT
goto MAIN


REM =====================================================================
REM Действия пресетов
REM =====================================================================

:VHS_CRT
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE vhs_crt
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET vhs_crt --intensity %INTENSITY%
goto MAIN

:CAMCORDER_90S
call :ASK_INPUT_FILE
call :ASK_OUTPUT_FILE camcorder_90s
call :ASK_INTENSITY
call :ASK_ENCODER
call :RUN_PRESET camcorder_90s --intensity %INTENSITY%
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
REM Параметры (UI prompts)
REM =====================================================================

:ASK_INPUT_FILE
set "SRC_PATH="
echo.
echo [INFO] Нажмите Enter для папки input проекта или укажите путь.
set /p SRC_PATH=Файл или папка input [input] :
if not defined SRC_PATH set "SRC_PATH=%BASE_DIR%\input"
goto :eof

:ASK_OUTPUT_FILE
set "DST_PATH="
echo.
set /p DST_PATH=Выходной файл [output\out_%~1.mp4] :
if not defined DST_PATH set "DST_PATH=%BASE_DIR%\output\out_%~1.mp4"
goto :eof

:ASK_INTENSITY
set "INTENSITY="
echo.
echo Сила воздействия (масштабирует bleed, мягкость, шум):
echo   1 - 0.5  (едва заметно)
echo   2 - 1.0  (настроенный default)
echo   3 - 1.5  (заметно)
echo   4 - 2.0  (сильно)
set /p INTENSITY=Выбор или число [2] :
if not defined INTENSITY set "INTENSITY=1.0"
if /I "%INTENSITY%"=="1" set "INTENSITY=0.5"
if /I "%INTENSITY%"=="2" set "INTENSITY=1.0"
if /I "%INTENSITY%"=="3" set "INTENSITY=1.5"
if /I "%INTENSITY%"=="4" set "INTENSITY=2.0"
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
echo [запуск] retro/%PRESET%
echo          вход:    %SRC_PATH%
echo          выход:   %DST_PATH%
echo          энкодер: %ENCODER%
echo.
call :RUNPY "%CORE_DIR%\main.py" run --palette retro --preset %PRESET% --input "%SRC_PATH%" --output "%DST_PATH%" --encoder %ENCODER%%EXTRA%
echo.
if not defined AUDION_NO_PAUSE pause
goto :eof


REM =====================================================================
REM Plumbing
REM =====================================================================

:NO_PYTHON
cls
echo [ОШИБКА] Python оркестратора не найден.
echo Ожидается: runtime\python.exe
echo Запустите builder_main.cmd -^> [01] BUILD PORTABLE ENV
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
