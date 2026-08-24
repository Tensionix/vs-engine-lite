@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Audion VS Engine Lite - Install Portable FFmpeg Gyan Stable

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%A in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fA"

set "DL=%ROOT%\install\download"
set "FFMPEG_DIR=%ROOT%\Tools\ffmpeg"
set "FFMPEG_BIN=%FFMPEG_DIR%\bin"
set "TMP=%ROOT%\system_core\_ffmpeg_tmp"
set "GYAN_INSTALLER=%SCRIPT_DIR%\Install-Portable-FFmpeg-Gyan.ps1"
set "PS_EXE="
set "SEVENZIP_EXE="
set "NO_PAUSE=0"
if /I "%AUDION_NO_PAUSE%"=="1" set "NO_PAUSE=1"
set "PROVIDER="
set "SRC_BIN="
set "GYAN_VERSION=auto"

:PARSE_ARGS
if "%~1"=="" goto DONE_ARGS
if /I "%~1"=="/NOPAUSE" set "NO_PAUSE=1" & shift & goto PARSE_ARGS
if /I "%~1"=="--no-pause" set "NO_PAUSE=1" & shift & goto PARSE_ARGS
if /I "%~1"=="/VERSION" set "GYAN_VERSION=%~2" & shift & shift & goto PARSE_ARGS
if /I "%~1"=="--version" set "GYAN_VERSION=%~2" & shift & shift & goto PARSE_ARGS
shift
goto PARSE_ARGS
:DONE_ARGS

if exist "%ROOT%\system_core\powershell\pwsh.exe" set "PS_EXE=%ROOT%\system_core\powershell\pwsh.exe"
if not defined PS_EXE where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"

if exist "%ROOT%\system_core\7zip\7za.exe" set "SEVENZIP_EXE=%ROOT%\system_core\7zip\7za.exe"
if not defined SEVENZIP_EXE if exist "%ROOT%\Tools\7zip\bin\7za.exe" set "SEVENZIP_EXE=%ROOT%\Tools\7zip\bin\7za.exe"
if not defined SEVENZIP_EXE where 7za.exe >nul 2>nul && set "SEVENZIP_EXE=7za.exe"
if not defined SEVENZIP_EXE where 7z.exe >nul 2>nul && set "SEVENZIP_EXE=7z.exe"
if not defined SEVENZIP_EXE if defined PS_EXE if exist "%SCRIPT_DIR%\Ensure-7zip.ps1" (
  echo [BOOTSTRAP] Ensuring portable 7-Zip before FFmpeg...
  "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& { . '%SCRIPT_DIR%\Ensure-7zip.ps1'; Ensure-7za -ProjectRoot '%ROOT%' | Out-Null }"
  if exist "%ROOT%\system_core\7zip\7za.exe" set "SEVENZIP_EXE=%ROOT%\system_core\7zip\7za.exe"
)

if not exist "%DL%\" mkdir "%DL%" >nul 2>nul
if not exist "%FFMPEG_BIN%\" mkdir "%FFMPEG_BIN%" >nul 2>nul

echo ======================================================================
echo   AUDION VS ENGINE LITE - INSTALL PORTABLE FFMPEG GYAN STABLE
echo ======================================================================
echo Root:    %ROOT%
echo Target:  %FFMPEG_BIN%
echo DL:      %DL%
echo Version: %GYAN_VERSION% (driver-aware stable policy)
echo PS:      %PS_EXE%
if defined SEVENZIP_EXE echo 7-Zip:   %SEVENZIP_EXE%
echo.

if not defined PS_EXE goto ERR_POWERSHELL
if not defined SEVENZIP_EXE goto ERR_7ZIP
if not exist "%GYAN_INSTALLER%" goto ERR_DOWNLOADER

echo [1/4] Downloading and extracting FFmpeg Gyan FULL build...
call :TRY_PROVIDER "Gyan release full 7z" "%DL%\ffmpeg-gyan-release-full.7z" "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z" "7z"
if not defined SRC_BIN (
  echo [WARN] Gyan full static failed or did not contain ffmpeg/ffprobe. Trying full shared.
  call :TRY_PROVIDER "Gyan release full shared 7z" "%DL%\ffmpeg-gyan-release-full-shared.7z" "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z" "7z"
)
if not defined SRC_BIN goto ERR_DOWNLOAD

echo.
echo [OK] Provider: %PROVIDER%
echo [OK] Source:   %SRC_BIN%
echo.

echo [3/4] Copying binaries...
call :RESET_DIR "%FFMPEG_DIR%"
if errorlevel 1 goto ERR_COPY
mkdir "%FFMPEG_BIN%" >nul 2>nul
if not exist "%FFMPEG_BIN%\" goto ERR_COPY
rem Whole build, not just bin: LICENSE and README.txt travel with the binary.
rem README.txt is the only place holding the exact upstream commit, and GPL
rem requires the licence notices to be kept when the build is passed on.
xcopy /s /e /y /i "%SRC_BIN%..\*" "%FFMPEG_DIR%\" >nul
if errorlevel 2 goto ERR_COPY
if not exist "%FFMPEG_BIN%\ffmpeg.exe" goto ERR_COPY
if not exist "%FFMPEG_BIN%\ffprobe.exe" goto ERR_COPY

rem Corresponding Source for the GPL build: version and commit are read from
rem the README that has just been copied, so no version is hardcoded here.
if defined PS_EXE if exist "%SCRIPT_DIR%\Fetch-FFmpegSource.ps1" (
  "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Fetch-FFmpegSource.ps1" -ProjectRoot "%ROOT%"
)

echo [4/4] Verifying...
"%FFMPEG_BIN%\ffmpeg.exe" -hide_banner -version
if not "!ERRORLEVEL!"=="0" goto ERR_VERIFY
"%FFMPEG_BIN%\ffprobe.exe" -hide_banner -version
if not "!ERRORLEVEL!"=="0" goto ERR_VERIFY

where nvidia-smi.exe >nul 2>nul
if not errorlevel 1 (
  echo [NVENC] Running hardware encoder smoke test...
  "%FFMPEG_BIN%\ffmpeg.exe" -hide_banner -loglevel error -f lavfi -i color=size=256x256:rate=1 -frames:v 1 -c:v h264_nvenc -f null NUL
  if not "!ERRORLEVEL!"=="0" goto ERR_NVENC
  echo [NVENC] Hardware encoder test passed.
)

rd /s /q "%TMP%" >nul 2>nul

echo.
echo [SUCCESS] FFmpeg installed: %FFMPEG_BIN%
call :PAUSE_IF_NEEDED
exit /b 0

:TRY_PROVIDER
set "TRY_NAME=%~1"
set "TRY_ARCHIVE=%~2"
set "TRY_URL=%~3"
set "TRY_KIND=%~4"
set "TRY_VARIANT=full"
echo %TRY_URL% | findstr /I "shared" >nul && set "TRY_VARIANT=full-shared"
set "SRC_BIN="

if exist "%TMP%" rd /s /q "%TMP%" >nul 2>nul
mkdir "%TMP%" >nul 2>nul
if not exist "%TMP%\" exit /b 1

echo [TRY] %TRY_NAME%
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%GYAN_INSTALLER%" -ArchivePath "%TRY_ARCHIVE%" -Variant "%TRY_VARIANT%" -ReleaseVersion "%GYAN_VERSION%" -SevenZipPath "%SEVENZIP_EXE%"
if errorlevel 1 exit /b 1

if not exist "%TRY_ARCHIVE%" exit /b 1
for %%F in ("%TRY_ARCHIVE%") do echo [OK] Downloaded: %%~zF bytes

echo [2/4] Extracting %TRY_KIND%...
if /I "%TRY_KIND%"=="zip" (
  if not defined SEVENZIP_EXE exit /b 1
  "%SEVENZIP_EXE%" x "%TRY_ARCHIVE%" "-o%TMP%" -y
  if errorlevel 1 exit /b 1
) else (
  if not defined SEVENZIP_EXE exit /b 1
  "%SEVENZIP_EXE%" x "%TRY_ARCHIVE%" "-o%TMP%" -y
  if errorlevel 1 exit /b 1
)

call :FIND_FFMPEG_BIN
if not defined SRC_BIN exit /b 1
set "PROVIDER=%TRY_NAME%"
exit /b 0

:FIND_FFMPEG_BIN
set "SRC_BIN="
for /f "delims=" %%F in ('where /r "%TMP%" ffmpeg.exe 2^>nul') do (
  if not defined SRC_BIN (
    if exist "%%~dpFffprobe.exe" set "SRC_BIN=%%~dpF"
  )
)
if not defined SRC_BIN exit /b 1
if not exist "%SRC_BIN%ffmpeg.exe" exit /b 1
if not exist "%SRC_BIN%ffprobe.exe" exit /b 1
exit /b 0

:ERR_POWERSHELL
echo [ERROR] PowerShell was not found.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_7ZIP
echo [ERROR] 7-Zip was not found. Run install\Install-Portable-7Zip.cmd first.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_DOWNLOADER
echo [ERROR] Gyan installer helper was not found: %GYAN_INSTALLER%
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_DOWNLOAD
echo [ERROR] All FFmpeg FULL providers failed.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_COPY
echo [ERROR] Copy to Tools\ffmpeg\bin failed.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_NVENC
echo [ERROR] FFmpeg was installed, but the NVIDIA NVENC smoke test failed.
echo [ERROR] Check the selected FFmpeg release and NVIDIA driver compatibility.
call :PAUSE_IF_NEEDED
exit /b 1

:ERR_VERIFY
echo [ERROR] FFmpeg verification failed.
call :PAUSE_IF_NEEDED
exit /b 1

:RESET_DIR
set "TARGET_DIR=%~1"
if not defined TARGET_DIR exit /b 1
if /I not "%TARGET_DIR%"=="%FFMPEG_DIR%" exit /b 1
if exist "%TARGET_DIR%\" rd /s /q "%TARGET_DIR%" >nul 2>nul
mkdir "%TARGET_DIR%" >nul 2>nul
if not exist "%TARGET_DIR%\" exit /b 1
exit /b 0

:PAUSE_IF_NEEDED
if not "%NO_PAUSE%"=="1" pause
goto :eof
