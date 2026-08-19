@echo off
title Desinstallation de Jipeg
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "src\Uninstall-Jipeg.ps1"
