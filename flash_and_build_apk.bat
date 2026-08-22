@echo off
setlocal enabledelayedexpansion
title Xiao ESP32-C3 - Flash Firmware & Build Android APK

echo ======================================================================
echo   Seeed Studio XIAO ESP32C3 - All-in-One Flash & Android APK Builder
echo ======================================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "FIRMWARE_DIR=%SCRIPT_DIR%firmware"
set "APP_DIR=%SCRIPT_DIR%apps\companion_app"
set "OUTPUT_DIR=%SCRIPT_DIR%output\main"

:: -------------------------------------------------------------------------
:: [Phase 1/3] Pre-flight Tool Checks
:: -------------------------------------------------------------------------
echo [1/3] Checking prerequisites (PlatformIO & Flutter SDK)...

where pio >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] PlatformIO CLI ('pio') not found in system PATH.
    echo Attempting build via PlatformIO if available in standard locations...
)

where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter SDK not found in PATH!
    echo Please make sure Flutter is installed and added to your system PATH.
    echo.
    pause
    exit /b 1
)

echo       - Prerequisites verified.
echo.

:: -------------------------------------------------------------------------
:: [Phase 2/3] Build & Flash ESP32-C3 Firmware
:: -------------------------------------------------------------------------
echo ======================================================================
echo [2/3] Building & Flashing Firmware to XIAO ESP32C3...
echo ======================================================================
echo.

pushd "%FIRMWARE_DIR%"
call pio run -t upload
set FLASH_ERR=%ERRORLEVEL%
popd

if %FLASH_ERR% NEQ 0 (
    echo.
    echo ======================================================================
    echo   [ERROR] Firmware Flashing Failed! (Exit Code: %FLASH_ERR%)
    echo ======================================================================
    echo   Troubleshooting Tips:
    echo   1. Ensure the XIAO ESP32C3 is firmly plugged into USB.
    echo   2. Close any open Serial Monitor or COM port connections.
    echo   3. Put device into Bootloader Mode:
    echo      Hold the 'B' (Boot) button, press and release 'R' (Reset),
    echo      then release 'B'.
    echo ======================================================================
    echo.
    pause
    exit /b %FLASH_ERR%
)

echo.
echo   [OK] Firmware successfully compiled and flashed to XIAO ESP32C3!
echo.

:: -------------------------------------------------------------------------
:: [Phase 3/3] Build Flutter Android APK (Release mode)
:: -------------------------------------------------------------------------
echo ======================================================================
echo [3/3] Building Android Companion App APK (Release mode)...
echo ======================================================================
echo.

pushd "%APP_DIR%"
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

:: Ensure output directory exists and copy release APK
if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%"
)

set "SOURCE_APK=%APP_DIR%\build\app\outputs\flutter-apk\app-release.apk"
set "DEST_APK=%OUTPUT_DIR%\xiao-companion-app.apk"
set "DEST_APK_NAMED=%OUTPUT_DIR%\app-release.apk"

if exist "%SOURCE_APK%" (
    copy /Y "%SOURCE_APK%" "%DEST_APK%" >nul
    copy /Y "%SOURCE_APK%" "%DEST_APK_NAMED%" >nul
) else (
    echo [WARNING] Source APK was not found at: %SOURCE_APK%
)

:: -------------------------------------------------------------------------
:: Final Summary & Next Steps
:: -------------------------------------------------------------------------
echo.
echo ======================================================================
echo   [SUCCESS] All tasks completed successfully!
echo ======================================================================
echo.
echo 1. Firmware:
echo    - Flashed to XIAO ESP32C3 board.
echo.
echo 2. Android Companion APK:
echo    - %DEST_APK%
echo    - %DEST_APK_NAMED%
echo.
echo Installation Options:
echo   - Direct ADB install:
echo       adb install -r "%DEST_APK%"
echo   - Or copy 'xiao-companion-app.apk' to your phone via USB/Cloud.
echo.

:: Check ADB device availability
where adb >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Checking for connected Android devices via ADB:
    adb devices
    echo.
)

:: Open output folder in Windows Explorer
if exist "%OUTPUT_DIR%" (
    explorer "%OUTPUT_DIR%"
)

echo ======================================================================
echo Done. Press any key to exit.
echo ======================================================================
pause
