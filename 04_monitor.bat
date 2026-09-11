@echo off
setlocal
title Dictula ESP32-C3 - Serial Monitor

echo ========================================================
echo   Dictula ESP32-C3 - Serial Monitor (115200)
echo ========================================================
echo   (Press Ctrl+C or Ctrl+T to exit)
echo.

pushd "%~dp0firmware"
call pio device monitor -b 115200 --dtr 1 --rts 1
popd

echo.
pause
