@echo off
setlocal enabledelayedexpansion
title Audio Vault ESP32-C3 - Full Flash Erase and Reset Tool

echo ======================================================================
echo   Audio Vault ESP32-C3 - Full Flash Erase and Storage Reset Tool
echo ======================================================================
echo.
echo [WARNING] This tool will completely wipe the entire Flash memory
echo           of the ESP32-C3, including:
echo             - All recorded audio files in LittleFS Flash storage
echo             - Wi-Fi and NVS non-volatile configuration
echo             - Current firmware
echo.
echo After erasing, it will automatically flash fresh firmware to
echo initialize a clean LittleFS filesystem partition.
echo.
echo Make sure:
echo   1. The Audio Vault ESP32-C3 is plugged into USB.
echo   2. All Serial Monitor windows (COM ports) are closed.
echo.
pause

echo.
echo ======================================================================
echo [1/3] Erasing entire ESP32-C3 Flash memory...
echo ======================================================================
echo.

pushd "%~dp0firmware"
call pio run -t erase
set ERASE_ERR=%ERRORLEVEL%
popd

if %ERASE_ERR% NEQ 0 (
    echo.
    echo ======================================================================
    echo   [ERROR] Flash erase failed!
    echo ======================================================================
    echo   Tips:
    echo   1. Check if the Audio Vault ESP32-C3 is firmly plugged into USB.
    echo   2. Make sure no other Serial Monitor / COM tool is open.
    echo   3. If needed, enter Bootloader Mode:
    echo      Hold the B [Boot] button, press and release R [Reset],
    echo      then release B.
    echo ======================================================================
    echo.
    pause
    exit /b %ERASE_ERR%
)

echo.
echo ======================================================================
echo [2/3] Flashing fresh firmware to initialize clean LittleFS filesystem...
echo ======================================================================
echo.

pushd "%~dp0firmware"
call pio run -t upload
set FLASH_ERR=%ERRORLEVEL%
popd

if %FLASH_ERR% NEQ 0 (
    echo.
    echo ======================================================================
    echo   [ERROR] Firmware upload after erase failed!
    echo ======================================================================
    pause
    exit /b %FLASH_ERR%
)

echo.
echo ======================================================================
echo [3/3] Flash erased and fresh firmware uploaded successfully!
echo       Starting Serial Monitor (115200 Baud)...
echo       (Press Ctrl+C or Ctrl+T to exit monitor)
echo ======================================================================
echo.

echo Waiting for USB serial CDC to re-enumerate...
ping -n 3 127.0.0.1 >nul

pushd "%~dp0firmware"
call pio device monitor -b 115200
popd

echo.
pause
