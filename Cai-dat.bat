@echo off
setlocal
chcp 65001 >nul
title Cai dat Windows ToDo Popup
echo.
if exist "%~dp0install.ps1" goto run
echo  Khong tim thay file install.ps1.
echo  Ban hay GIAI NEN file zip truoc (chuot phai ^> Extract All), roi chay lai Cai-dat.bat.
echo.
pause
exit /b 1
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
