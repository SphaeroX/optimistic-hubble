@echo off
setlocal
title Xiao ESP32-C3 - Serial Monitor

echo ========================================================
echo   Seeed Studio XIAO ESP32C3 - Serial Monitor (115200)
echo ========================================================
echo   Interactive Keys:
echo     'm' -> Switch to Dashboard / VU-Meter Mode
echo     'p' -> Switch to Serial Plotter Mode
echo     'i' -> Re-scan I2C & Re-run Self-Test
echo     'h' -> Show Help
echo.
echo   Press Ctrl+C or Ctrl+T to exit monitor.
echo ========================================================
echo.

pio device monitor -b 115200

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================================
    echo   [INFO] Monitor closed or disconnected.
    echo ========================================================
    pause
)
