@echo off
setlocal
title Xiao ESP32-C3 - Flash and Monitor

echo ========================================================
echo   Seeed Studio XIAO ESP32C3 - Flash and Monitor Tool
echo ========================================================
echo.
echo [1/2] Building and flashing firmware to XIAO ESP32C3...
echo.

pushd "%~dp0firmware"
pio run -t upload
set FLASH_ERR=%ERRORLEVEL%
popd

if %FLASH_ERR% NEQ 0 (
    echo.
    echo ========================================================
    echo   [ERROR] Flashing failed!
    echo ========================================================
    echo   Tips:
    echo   1. Check if the XIAO ESP32C3 is firmly plugged into USB.
    echo   2. Make sure no other Serial Monitor / COM tool is open.
    echo   3. If needed, enter Bootloader Mode:
    echo      Hold the 'B' (Boot) button, press and release 'R' (Reset),
    echo      then release 'B'.
    echo ========================================================
    echo.
    pause
    exit /b %FLASH_ERR%
)

echo.
echo ========================================================
echo   [SUCCESS] Firmware uploaded successfully!
echo   Starting Serial Monitor (115200 Baud)...
echo   (Press Ctrl+C or Ctrl+T to exit monitor)
echo ========================================================
echo.

REM Small delay to give USB CDC time to re-enumerate
timeout /t 2 /nobreak >nul

pushd "%~dp0firmware"
pio device monitor -b 115200
popd

echo.
pause
