@echo off
chcp 936 >nul
title 恢复备份
cd /d "%~dp0"
set "KSS=%USERPROFILE%\.kss\manage-screensaver.ps1"
if not exist "%KSS%" set "KSS=%~dp0manage-screensaver.ps1"
if not exist "%KSS%" (
  echo 找不到工具。请先双击"1-一键安装.bat"。
  echo.
  pause
  exit /b 1
)
echo 提示：开始之前，先按一下 Kindle 的电源键，让屏幕亮起来。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%KSS%" rollback -Yes
echo.
pause
