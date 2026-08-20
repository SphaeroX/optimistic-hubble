@echo off
setlocal
title Xiao ESP32-C3 - Firmware Build

echo ========================================================
echo   Seeed Studio XIAO ESP32C3 - Compiling Firmware...
echo ========================================================
echo.

pushd "%~dp0firmware"
pio run
set BUILD_ERR=%ERRORLEVEL%
popd

if %BUILD_ERR% EQU 0 (
    echo.
    echo ========================================================
    echo   [SUCCESS] Firmware build completed with 0 errors!
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo   [FAILED] Build failed! Check compiler output above.
    echo ========================================================
)

echo.
pause
