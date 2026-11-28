@echo off
chcp 936 >nul
title 检查 Kindle
cd /d "%~dp0"
set "KSS=%USERPROFILE%\.kss\manage-screensaver.ps1"
if not exist "%KSS%" set "KSS=%~dp0manage-screensaver.ps1"
if not exist "%KSS%" (
  echo 找不到工具。请先双击"1-一键安装.bat"。
  echo.
  pause
  exit /b 1
)
echo 先按一下 Kindle 的电源键，让屏幕亮起来，再等半分钟。
echo 这个窗口会告诉你设备正不正常。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%KSS%" conn
echo.
echo 上面只要能看到"屏幕"后面有数字，设备就是正常的。
echo.
pause
