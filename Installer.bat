@echo off
title Installation de Jipeg
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "src\Install-Jipeg.ps1"
if errorlevel 1 (
  echo.
  echo Echec de l installation.
  pause
)
