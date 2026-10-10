@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Space Rangers HD 简体中文语言包卸载器 v1.0
echo 请先退出游戏。卸载会还原安装时备份的文件。
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer.ps1" -Mode Uninstall
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
