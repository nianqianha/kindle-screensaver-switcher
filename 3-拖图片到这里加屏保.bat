@echo off
chcp 936 >nul
title 加屏保
cd /d "%~dp0"
set "KSS=%USERPROFILE%\.kss\manage-screensaver.ps1"
if not exist "%KSS%" set "KSS=%~dp0manage-screensaver.ps1"
if not exist "%KSS%" (
  echo 找不到工具。请先双击"1-一键安装.bat"。
  echo.
  pause
  exit /b 1
)
if "%~1"=="" (
  echo 这个图标不是双击用的。
  echo 用法：用鼠标按住一张图片，拖到这个图标上，松开鼠标。
  echo 可以一次拖好几张。
  echo.
  pause
  exit /b 0
)
echo 提示：开始之前，先按一下 Kindle 的电源键，让屏幕亮起来。
echo 加图过程中会问你"确认添加"，按 y 然后回车。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%KSS%" add %* -Yes
echo.
pause
