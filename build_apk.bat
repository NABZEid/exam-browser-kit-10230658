@echo off
cd /d "%~dp0exam_browser"
call flutter build apk --release
echo.
echo APK: %cd%\build\app\outputs\flutter-apk\app-release.apk
pause
