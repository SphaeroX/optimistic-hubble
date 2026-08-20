@echo off
setlocal
title Xiao ESP32-C3 - Serial Monitor

echo ========================================================
echo   Seeed Studio XIAO ESP32C3 - Serial Monitor (115200)
echo ========================================================
echo   (Press Ctrl+C or Ctrl+T to exit)
echo.

pushd "%~dp0firmware"
pio device monitor -b 115200
popd

echo.
pause
