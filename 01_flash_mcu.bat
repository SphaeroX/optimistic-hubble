@echo off
setlocal
title Dictula ESP32-C3 - Flash and Monitor

echo ========================================================
echo   Dictula ESP32-C3 V2 - Flash and Monitor Tool
echo ========================================================
echo.
echo [1/2] Building and flashing firmware to ESP32-C3...
echo.

pushd "%~dp0firmware"
call pio run -t upload
set FLASH_ERR=%ERRORLEVEL%
popd

if %FLASH_ERR% NEQ 0 (
    echo.
    echo ========================================================
    echo   [ERROR] Flashing failed!
    echo ========================================================
    echo   Tips:
    echo   1. Check if the ESP32-C3 is firmly plugged into USB.
    echo   2. Make sure no other Serial Monitor / COM tool is open.
    echo   3. If needed, enter Bootloader Mode:
    echo      Hold the B [Boot] button, press and release R [Reset],
    echo      then release B.
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

REM Safe delay using ping to give USB CDC time to re-enumerate without redirection crashes
echo Waiting for device USB serial to reconnect...
ping -n 3 127.0.0.1 >nul

pushd "%~dp0firmware"
call pio device monitor -b 115200
popd

echo.
pause
