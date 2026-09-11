@echo off
setlocal
title Dictula ESP32-C3 - Serial Monitor

echo ========================================================
echo   Dictula ESP32-C3 - Serial Monitor (115200)
echo ========================================================
echo   Keys inside monitor:
echo     r = Software Restart MCU
echo     b = Print System Summary / Banner
echo     w = Toggle Wi-Fi SoftAP
echo     s = Toggle Audio Recording
echo     Ctrl+C = Exit Monitor
echo ========================================================
echo.

pushd "%~dp0firmware"
call pio device monitor -b 115200 --dtr 1 --rts 1
popd

echo.
pause
