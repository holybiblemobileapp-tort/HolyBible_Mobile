@echo off
setlocal
echo ==========================================
echo   Holy Bible Mobile - Device Selector
echo ==========================================
echo.

:: Check if flutter is in path
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Flutter SDK not found in your system PATH.
    pause
    exit /b
)

echo [1/2] Detecting connected devices...
call flutter devices
echo.

echo [2/2] Starting application...
echo.
echo Choose an option:
echo [1] Run on ALL devices (including computer)
echo [2] Run on your SAMSUNG (de5427d7)
echo [3] Type a different Device ID
echo.

set /p choice="Enter choice (1, 2, or 3): "

if "%choice%"=="1" (
    call flutter run -d all
) else if "%choice%"=="2" (
    echo Starting on SAMSUNG...
    call flutter run -d de5427d7
) else if "%choice%"=="3" (
    set /p deviceid="Enter the Device ID from the list above: "
    call flutter run -d %deviceid%
) else (
    echo Invalid choice.
)

echo.
echo Press any key to exit...
pause >nul
