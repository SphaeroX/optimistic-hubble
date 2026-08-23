@echo off
setlocal
title Xiao ESP32-C3 - Flutter Companion App (Windows)

echo ========================================================
echo   Xiao ESP32-C3 Audio Companion - Flutter Windows App
echo ========================================================
echo.

set PATH=C:\src\flutter\bin;%PATH%

pushd "%~dp0apps\companion_app"

echo Launching Flutter App on Windows Desktop...
flutter run -d windows

popd

pause
