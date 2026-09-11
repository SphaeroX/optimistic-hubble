@echo off
setlocal
title Audio Vault Companion - Flutter Windows App

echo ========================================================
echo   Audio Vault Audio Companion - Flutter Windows App
echo ========================================================
echo.

set PATH=C:\src\flutter\bin;%PATH%

pushd "%~dp0apps\companion_app"

echo Launching Flutter App on Windows Desktop...
flutter run -d windows

popd

pause
