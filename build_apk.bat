@echo off
setlocal enabledelayedexpansion
title Xiao Audio Companion - Build Android APK

echo ======================================================================
echo   Seeed Studio XIAO Audio Recorder - Build Android APK
echo ======================================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%SCRIPT_DIR%apps\companion_app"
set "OUTPUT_DIR=%SCRIPT_DIR%output\main"

:: Check if Flutter is available
where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter SDK not found in PATH!
    echo Please make sure Flutter is installed and added to your system PATH.
    echo.
    pause
    exit /b 1
)

:: Navigate to companion app folder
echo [1/3] Navigating to Flutter companion app directory...
pushd "%APP_DIR%"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Could not find folder: %APP_DIR%
    pause
    exit /b 1
)

echo [2/3] Building Android APK (Release mode)...
echo This may take a couple of minutes on the first build.
echo.

call flutter build apk --release
set BUILD_STATUS=%ERRORLEVEL%
popd

if %BUILD_STATUS% NEQ 0 (
    echo.
    echo ======================================================================
    echo   [FAILED] Flutter APK build failed! Check errors above.
    echo ======================================================================
    echo.
    pause
    exit /b %BUILD_STATUS%
)

:: Ensure output directories exist
echo.
echo [3/3] Copying APK to output directory...
if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%"
)

set "SOURCE_APK=%APP_DIR%\build\app\outputs\flutter-apk\app-release.apk"
set "DEST_APK=%OUTPUT_DIR%\xiao-companion-app.apk"
set "DEST_APK_NAMED=%OUTPUT_DIR%\app-release.apk"

if exist "%SOURCE_APK%" (
    copy /Y "%SOURCE_APK%" "%DEST_APK%" >nul
    copy /Y "%SOURCE_APK%" "%DEST_APK_NAMED%" >nul
    
    echo.
    echo ======================================================================
    echo   [SUCCESS] APK build and packaging completed successfully!
    echo ======================================================================
    echo.
    echo Output files:
    echo   - %DEST_APK%
    echo   - %DEST_APK_NAMED%
    echo.
    echo Installation Options:
    echo   1. Transfer 'xiao-companion-app.apk' to your Android smartphone
    echo      via USB cable, Google Drive, WhatsApp, or local network.
    echo   2. Or install directly via ADB if your phone is connected:
    echo      adb install -r "%DEST_APK%"
    echo.
    
    :: Check if ADB is available and device connected
    where adb >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo Checking for connected Android devices via ADB...
        adb devices
        echo.
    )
    
    :: Open destination folder in Windows Explorer
    explorer "%OUTPUT_DIR%"
) else (
    echo [WARNING] Source APK was not found at: %SOURCE_APK%
)

echo.
pause
