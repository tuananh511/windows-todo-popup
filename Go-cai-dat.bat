@echo off
chcp 65001 >nul
title Go cai dat Windows ToDo Popup
if exist "%~dp0uninstall.ps1" goto run
echo  Khong tim thay file uninstall.ps1.
pause
exit /b 1
:run
copy /y "%~dp0uninstall.ps1" "%TEMP%\wtp-uninstall.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\wtp-uninstall.ps1" & del "%TEMP%\wtp-uninstall.ps1" >nul 2>&1 & exit /b
