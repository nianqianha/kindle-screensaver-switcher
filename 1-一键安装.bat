@echo off
chcp 936 >nul
title Kindle 屏保工具 - 安装
cd /d "%~dp0"
echo.
echo ========================================
echo   Kindle 屏保工具 - 安装
echo ========================================
echo.
echo 这一步只要做一次。装好以后，换屏保只要双击另一个图标。
echo.
if not exist "%~dp0install.ps1" (
  echo 出错了：没找到 install.ps1。
  echo 请把 install.ps1 和这些 bat 放在同一个文件夹里。
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
if errorlevel 1 (
  echo 安装没成功。请把屏幕上的字拍下来，发给懂电脑的人看。
) else (
  echo 装好了。以后换屏保，双击"2-打开工具.bat"就行。
)
echo.
pause
