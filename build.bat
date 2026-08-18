@echo off
setlocal
title Xiao ESP32-C3 - Build

echo ========================================================
echo   Seeed Studio XIAO ESP32C3 - Compiling Project...
echo ========================================================
echo.

pio run

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo   [SUCCESS] Build completed with 0 errors!
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo   [FAILED] Build failed! Check compiler output above.
    echo ========================================================
)

echo.
pause
