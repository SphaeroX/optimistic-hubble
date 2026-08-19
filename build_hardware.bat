@echo off
setlocal
echo ======================================================================
echo  ESP32-C3 Voice Recorder - Python KiCad Schematic Generator
echo ======================================================================

if not exist "%~dp0hardware\.venv\Scripts\python.exe" (
    echo [INFO] Creating virtual environment in hardware\.venv ...
    python -m venv "%~dp0hardware\.venv"
    "%~dp0hardware\.venv\Scripts\pip.exe" install -r "%~dp0hardware\requirements.txt"
)

echo [INFO] Generating KiCad 8 Schematic, Netlist, and Bill of Materials...
"%~dp0hardware\.venv\Scripts\python.exe" "%~dp0hardware\generate_schematic.py"

if %ERRORLEVEL% equ 0 (
    echo [SUCCESS] KiCad export completed successfully!
    echo Output directory: %~dp0hardware\output
) else (
    echo [ERROR] Generation failed. Please check the log messages above.
)

pause
