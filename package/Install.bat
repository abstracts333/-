@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Space Rangers HD 简体中文语言包安装器 v1.0
echo 请先退出游戏，并将本安装包完整解压到本地。
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer.ps1" -Mode Install
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
