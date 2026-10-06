@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\package_windows.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. Read the message above and WINDOWS-BUILD.fa.md.
  pause
  exit /b 1
)
echo.
echo The installer is ready in the dist folder.
pause
