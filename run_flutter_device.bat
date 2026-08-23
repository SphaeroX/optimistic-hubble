@echo off
setlocal
title Xiao Audio Companion - Flutter Device Run

echo ========================================================
echo   Xiao Audio Companion - Run on Connected Device
echo ========================================================
echo.

set PATH=C:\src\flutter\bin;%PATH%

pushd "%~dp0apps\companion_app"

echo Launching Flutter App on connected device...
echo.
flutter run

popd

pause
