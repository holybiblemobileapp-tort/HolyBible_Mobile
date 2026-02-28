@echo off
echo ==========================================
echo   Holy Bible Mobile - Building Release APK
echo ==========================================
echo.

echo [1/2] Cleaning previous builds...
call flutter clean

echo [2/2] Building APK (Release mode)...
call flutter build apk --release

echo.
echo ==========================================
echo   BUILD COMPLETE
echo ==========================================
echo.
echo Your shareable file is located at:
echo build\app\outputs\flutter-apk\app-release.apk
echo.
pause
