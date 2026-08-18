@echo off
setlocal
title Xiao Voice Companion - Local Server

echo ========================================================
echo   XIAO ESP32C3 - Web Voice Companion
echo ========================================================
echo.
echo Starting local web server at http://localhost:8000 ...
echo Opening your default browser...
echo.
echo Press Ctrl+C in this window to stop the server.
echo ========================================================
echo.

REM Open browser after 1 second
start "" http://localhost:8000

REM Run Python Companion Proxy Server
python app\server.py

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Python not found, trying basic file launch...
    start "" app\index.html
    pause
)
