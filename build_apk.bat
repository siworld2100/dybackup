@echo off
REM ============================================================
REM  Build release APK for dybackup
REM  Requires: Flutter SDK on PATH, Android SDK installed
REM
REM  Notes:
REM    - GRADLE_USER_HOME points to D: because C: has too little
REM      free space for Gradle transforms.
REM    - TEMP is redirected to D: for the same reason.
REM    - NO_PROXY is set so Flutter's local test hooks work when a
REM      system HTTP proxy is configured.
REM    - This file is deliberately ASCII-only: cmd.exe reads it in the
REM      system ANSI code page, and UTF-8 Chinese text inside a bat can
REM      corrupt the following line during FOR /F parsing.
REM    - Update address and signing key are NOT in the repo. They are
REM      read from tools\server\secret.env (gitignored) and passed to
REM      Flutter as --dart-define at build time.
REM ============================================================
setlocal enabledelayedexpansion

cd /d "%~dp0"

set "GRADLE_USER_HOME=D://dev-cache//gradle-home"
set "TMP=D://dev-cache//tmp"
set "TEMP=D://dev-cache//tmp"
set "NO_PROXY=localhost,127.0.0.1,::1"
set "no_proxy=localhost,127.0.0.1,::1"

if not exist "%TMP%" mkdir "%TMP%"

REM ---- read build-time values from secret.env ----
set "DART_DEFINES="
set "SECRET_FILE=%~dp0tools\server\secret.env"
if exist "%SECRET_FILE%" (
  for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%SECRET_FILE%") do (
    if /i "%%a"=="MANIFEST_KEY" set "DART_DEFINES=!DART_DEFINES! --dart-define=MANIFEST_KEY=%%b"
    if /i "%%a"=="MANIFEST_URL" set "DART_DEFINES=!DART_DEFINES! --dart-define=MANIFEST_URL=%%b"
  )
)
if "%DART_DEFINES%"=="" (
  echo [WARN] tools\server\secret.env not found or has no MANIFEST_KEY / MANIFEST_URL
  echo [WARN] Online update will be DISABLED in this build. Everything else works.
) else (
  echo [INFO] dart-defines:%DART_DEFINES%
)

echo [1/3] flutter pub get
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [2/3] flutter analyze
call dart analyze .
if errorlevel 1 goto :fail

echo.
echo [3/3] flutter build apk --release
call flutter build apk --release%DART_DEFINES%
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo  BUILD OK
echo  APK: %~dp0build\app\outputs\flutter-apk\app-release.apk
echo ============================================================
goto :end

:fail
echo.
echo ============================================================
echo  BUILD FAILED
echo ============================================================

:end
endlocal
pause
