@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

title Audion VS Engine - Главный лаунчер (Русский)

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
cd /d "%BASE_DIR%"

set "CORE_DIR=%BASE_DIR%\system_core"
set "RUNTIME_DIR=%BASE_DIR%\._runtime"
set "MENU_FILE=%RUNTIME_DIR%\project_menu_ru.txt"
set "RES_FILE=%RUNTIME_DIR%\project_menu_ru_res.txt"

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
echo   AUDION VS ENGINE
echo   Технический препроцесс + Плёночные луки + Ретро
echo ======================================================================
echo Корень:    %BASE_DIR%
echo Python:    %PYTHON_CMD% %PYTHON_ARGS%
echo Меню:      %MENU_MODE%
echo.

if defined FZF_CMD goto FZF_MENU
goto FALLBACK_MENU

:FZF_MENU
> "%MENU_FILE%" echo === Движки (выберите палитру) =====================================
>>"%MENU_FILE%" echo [01] Precision Engine                 ^| precision      ^| шумодав / дебанд / зерно (технический)
>>"%MENU_FILE%" echo [02] Film Looks Engine                ^| film_looks     ^| Cinematic / 35mm / 16mm / Super 8 / Bleach Bypass
>>"%MENU_FILE%" echo [03] Retro Engine                     ^| retro          ^| VHS / CRT / Camcorder 90s
>>"%MENU_FILE%" echo [3a] Restoration Engine               ^| restoration    ^| QTGMC / TIVTC / MCDeGrain / deblock / dehaze / NNEDI3 2x
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Сервис ========================================================
>>"%MENU_FILE%" echo [04] Доктор (полная диагностика)      ^| doctor         ^| VS / плагины / FFmpeg / CUDA
>>"%MENU_FILE%" echo [05] Список пресетов                  ^| list_presets   ^| имена + параметры по умолчанию
>>"%MENU_FILE%" echo [06] Список энкодеров                 ^| list_encoders  ^| H.264 / H.265 / ProRes / DNxHR
>>"%MENU_FILE%" echo [07] Информация о проекте             ^| info           ^| пути и версии
>>"%MENU_FILE%" echo [08] Анализ файла                     ^| probe          ^| ffprobe summary (JSON)
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Открыть папки =================================================
>>"%MENU_FILE%" echo [09] Открыть папку input              ^| open_input     ^| Explorer
>>"%MENU_FILE%" echo [10] Открыть папку output             ^| open_output    ^| Explorer
>>"%MENU_FILE%" echo [11] Открыть папку logs               ^| open_logs      ^| JSON отчёты
>>"%MENU_FILE%" echo [12] Открыть папку config             ^| open_config    ^| настройки
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Профили =======================================================
>>"%MENU_FILE%" echo [13] Применить профиль к файлу, папке ^| apply_profile  ^| 5 встроенных + кастомные JSON в config\profiles
>>"%MENU_FILE%" echo.
>>"%MENU_FILE%" echo === Сборка / язык =================================================
>>"%MENU_FILE%" echo [14] Tools / Builder                  ^| tools          ^| install layer + release
>>"%MENU_FILE%" echo [15] Switch to English                ^| launcher_en    ^| перейти на EN
>>"%MENU_FILE%" echo [00] Выход                            ^| exit           ^| закрыть

"%FZF_CMD%" --prompt="audion@main-ru > " --pointer=">" --header="Выберите движок, сервис или переключите язык." --layout=reverse --border=rounded --info=hidden --margin=1,2 < "%MENU_FILE%" > "%RES_FILE%"

set "CHOICE="
set /p CHOICE=<"%RES_FILE%"
if not defined CHOICE goto MAIN

for /f "tokens=2 delims=|" %%a in ("%CHOICE%") do set "RAW=%%a"
call :TRIM RAW

if /I "%RAW%"=="precision"     goto PRECISION
if /I "%RAW%"=="film_looks"    goto FILM_LOOKS
if /I "%RAW%"=="retro"         goto RETRO
if /I "%RAW%"=="restoration"   goto RESTORATION
if /I "%RAW%"=="doctor"        goto DOCTOR
if /I "%RAW%"=="list_presets"  goto LIST_PRESETS
if /I "%RAW%"=="list_encoders" goto LIST_ENCODERS
if /I "%RAW%"=="info"          goto INFO
if /I "%RAW%"=="probe"         goto PROBE
if /I "%RAW%"=="open_input"    goto OPEN_INPUT
if /I "%RAW%"=="open_output"   goto OPEN_OUTPUT
if /I "%RAW%"=="open_logs"     goto OPEN_LOGS
if /I "%RAW%"=="open_config"   goto OPEN_CONFIG
if /I "%RAW%"=="apply_profile" goto APPLY_PROFILE
if /I "%RAW%"=="tools"         goto TOOLS
if /I "%RAW%"=="launcher_en"   goto LAUNCHER_EN
if /I "%RAW%"=="exit"          exit /b 0
goto MAIN

:FALLBACK_MENU
echo === Движки ===
echo [P] Precision Engine     (шумодав / дебанд / зерно)
echo [F] Film Looks Engine    (Cinematic / 35mm / 16mm / Super 8)
echo [R] Retro Engine         (VHS / CRT / Camcorder 90s)
echo [N] Restoration Engine   (QTGMC / TIVTC / MCDeGrain / deblock / dehaze / NNEDI3 2x)
echo.
echo === Сервис ===
echo [D] Доктор
echo [L] Список пресетов
echo [E] Список энкодеров
echo [I] Информация
echo [B] Анализ файла
echo.
echo === Папки ===
echo [1] Открыть папку input
echo [2] Открыть папку output
echo [3] Открыть папку logs
echo [4] Открыть папку config
echo.
echo === Профили ===
echo [A] Применить профиль к файлу или папке
echo.
echo === Сборка / язык ===
echo [T] Tools / Builder
echo [U] Switch to English
echo [0] Выход
echo.
choice /C PFRNDLEIB1234ATU0 /N /M "Выбор: "
if errorlevel 17 exit /b 0
if errorlevel 16 goto LAUNCHER_EN
if errorlevel 15 goto TOOLS
if errorlevel 14 goto APPLY_PROFILE
if errorlevel 13 goto OPEN_CONFIG
if errorlevel 12 goto OPEN_LOGS
if errorlevel 11 goto OPEN_OUTPUT
if errorlevel 10 goto OPEN_INPUT
if errorlevel 9  goto PROBE
if errorlevel 8  goto INFO
if errorlevel 7  goto LIST_ENCODERS
if errorlevel 6  goto LIST_PRESETS
if errorlevel 5  goto DOCTOR
if errorlevel 4  goto RESTORATION
if errorlevel 3  goto RETRO
if errorlevel 2  goto FILM_LOOKS
if errorlevel 1  goto PRECISION
goto MAIN


REM =====================================================================
REM Engine dispatch
REM =====================================================================

:PRECISION
if exist "%BASE_DIR%\cli\launcher_precision_ru.cmd" (
  call "%BASE_DIR%\cli\launcher_precision_ru.cmd"
) else (
  call "%BASE_DIR%\cli\launcher_precision.cmd"
)
goto MAIN

:FILM_LOOKS
if exist "%BASE_DIR%\cli\launcher_film_looks_ru.cmd" (
  call "%BASE_DIR%\cli\launcher_film_looks_ru.cmd"
) else (
  call "%BASE_DIR%\cli\launcher_film_looks.cmd"
)
goto MAIN

:RETRO
if exist "%BASE_DIR%\cli\launcher_retro_ru.cmd" (
  call "%BASE_DIR%\cli\launcher_retro_ru.cmd"
) else (
  call "%BASE_DIR%\cli\launcher_retro.cmd"
)
goto MAIN

:RESTORATION
if exist "%BASE_DIR%\cli\launcher_restoration_ru.cmd" (
  call "%BASE_DIR%\cli\launcher_restoration_ru.cmd"
) else (
  call "%BASE_DIR%\cli\launcher_restoration.cmd"
)
goto MAIN


REM =====================================================================
REM Сервис
REM =====================================================================

:DOCTOR
call :RUNPY "%CORE_DIR%\doctor.py"
if not defined AUDION_NO_PAUSE pause
goto MAIN

:LIST_PRESETS
call :RUNPY "%CORE_DIR%\main.py" list-presets
if not defined AUDION_NO_PAUSE pause
goto MAIN

:LIST_ENCODERS
call :RUNPY "%CORE_DIR%\main.py" list-encoders
if not defined AUDION_NO_PAUSE pause
goto MAIN

:INFO
call :RUNPY "%CORE_DIR%\main.py" info
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


REM =====================================================================
REM Папки
REM =====================================================================

:OPEN_INPUT
start "" explorer "%BASE_DIR%\input"
goto MAIN

:OPEN_OUTPUT
start "" explorer "%BASE_DIR%\output"
goto MAIN

:OPEN_LOGS
start "" explorer "%BASE_DIR%\logs"
goto MAIN

:OPEN_CONFIG
start "" explorer "%BASE_DIR%\config"
goto MAIN


REM =====================================================================
REM Профили
REM =====================================================================

:APPLY_PROFILE
cls
echo ======================================================================
echo   ПРИМЕНИТЬ ПРОФИЛЬ К ФАЙЛУ ИЛИ ПАПКЕ
echo ======================================================================
echo Доступные профили (встроенные + пользовательские JSON в config\profiles):
echo.
call :RUNPY "%CORE_DIR%\main.py" list-profiles
if errorlevel 1 ( pause & goto MAIN )
echo.
set "PROF_NAME="
set /p PROF_NAME=Имя профиля (первая колонка):
call :TRIM PROF_NAME
if not defined PROF_NAME goto MAIN

echo.
echo Применить к:
echo   [F] Один файл
echo   [D] Папка (батч всех видео)
echo   [C] Отмена
choice /C FDC /N /M "Выбор: "
if errorlevel 3 goto MAIN
if errorlevel 2 goto APPLY_FOLDER
if errorlevel 1 goto APPLY_FILE

:APPLY_FILE
echo.
set "SRC_PATH="
set /p SRC_PATH=Путь к файлу (drag-and-drop или вставить):
set "SRC_PATH=%SRC_PATH:"=%"
if not defined SRC_PATH goto MAIN
if not exist "%SRC_PATH%" (
  echo [ERROR] Файл не найден: %SRC_PATH%
  if not defined AUDION_NO_PAUSE pause & goto MAIN
)
set "DST_PATH="
set /p DST_PATH=Путь сохранения [Enter = output\^<имя^>__%PROF_NAME%.mp4]:
set "DST_PATH=%DST_PATH:"=%"
if not defined DST_PATH (
  for %%I in ("%SRC_PATH%") do set "DST_PATH=%BASE_DIR%\output\%%~nI__%PROF_NAME%.mp4"
)
echo.
echo [run] apply-profile %PROF_NAME%
echo       in:  %SRC_PATH%
echo       out: %DST_PATH%
echo       audio: auto copy; ProRes -> lossy = AAC 384k
echo.
call :RUNPY "%CORE_DIR%\main.py" apply-profile --name "%PROF_NAME%" --input "%SRC_PATH%" --output "%DST_PATH%"
echo.
if not defined AUDION_NO_PAUSE pause
goto MAIN

:APPLY_FOLDER
echo.
set "SRC_DIR="
set /p SRC_DIR=Папка-источник [Enter = input\]:
set "SRC_DIR=%SRC_DIR:"=%"
if not defined SRC_DIR set "SRC_DIR=%BASE_DIR%\input"
if not exist "%SRC_DIR%" (
  echo [ERROR] Папка не найдена: %SRC_DIR%
  if not defined AUDION_NO_PAUSE pause & goto MAIN
)
set "DST_DIR="
set /p DST_DIR=Папка назначения [Enter = output\]:
set "DST_DIR=%DST_DIR:"=%"
if not defined DST_DIR set "DST_DIR=%BASE_DIR%\output"
echo.
choice /C YN /N /M "Заходить во вложенные папки? [Y] да / [N] нет: "
set "REC_FLAG=--recursive"
if errorlevel 2 set "REC_FLAG="
echo.
echo [run] apply-profile-batch %PROF_NAME%
echo       in:  %SRC_DIR%
echo       out: %DST_DIR%
echo       %REC_FLAG%
echo       audio: auto copy; ProRes -> lossy = AAC 384k
echo.
call :RUNPY "%CORE_DIR%\main.py" apply-profile-batch --name "%PROF_NAME%" --input-dir "%SRC_DIR%" --output-dir "%DST_DIR%" %REC_FLAG%
echo.
if not defined AUDION_NO_PAUSE pause
goto MAIN


REM =====================================================================
REM Сборка / язык
REM =====================================================================

:TOOLS
call "%BASE_DIR%\launcher_tools.cmd"
goto MAIN

:LAUNCHER_EN
call "%BASE_DIR%\launcher_project.cmd"
goto MAIN


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
