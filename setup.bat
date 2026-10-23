@echo off
cd /d "%~dp0"
where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter tidak ditemukan di PATH.
  pause
  exit /b 1
)

if not exist exam_browser (
  call flutter create --platforms=android,windows --org com.examsafe exam_browser
  if errorlevel 1 (
    echo Gagal membuat proyek.
    pause
    exit /b 1
  )
)

copy /y pubspec.yaml exam_browser\pubspec.yaml
copy /y main.dart exam_browser\lib\main.dart
copy /y AndroidManifest.xml exam_browser\android\app\src\main\AndroidManifest.xml
if not exist exam_browser\android\app\src\main\kotlin\com\examsafe\exam_browser mkdir exam_browser\android\app\src\main\kotlin\com\examsafe\exam_browser
copy /y MainActivity.kt exam_browser\android\app\src\main\kotlin\com\examsafe\exam_browser\MainActivity.kt
if exist exam_browser\test rmdir /s /q exam_browser\test

cd exam_browser
call flutter pub get
echo.
echo Selesai. Jalankan build_apk.bat atau build_windows.bat
pause
