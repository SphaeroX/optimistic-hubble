@echo off
setlocal
title Xiao Voice Companion - Legacy Web Prototype

echo ========================================================
echo   XIAO ESP32C3 - Web Bluetooth Prototype Server
echo ========================================================
echo.
echo Starting local web server at http://localhost:8000 ...
echo Opening your default browser (Chrome/Edge recommended)...
echo.
echo Press Ctrl+C in this window to stop the server.
echo ========================================================
echo.

pushd "%~dp0apps\web_prototype"

REM Open browser after 1 second
start "" http://localhost:8000

REM Run Python simple HTTP server serving the 'apps/web_prototype' directory
python -m http.server 8000

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Python not found, trying basic file launch...
    start "" index.html
    pause
)

popd
