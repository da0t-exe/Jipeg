@echo off
title Install Jipeg
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "src\Install-Jipeg.ps1"
if errorlevel 1 (
  echo.
  echo Installation failed.
  pause
)
