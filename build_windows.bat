@echo off
cd /d "%~dp0exam_browser"
call flutter build windows --release
echo.
echo EXE: %cd%\build\windows\x64\runner\Release\exam_browser.exe
pause
