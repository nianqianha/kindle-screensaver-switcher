@echo off
chcp 936 >nul
title Kindle 屏保选图工具
cd /d "%~dp0"
if not exist "%~dp0kss-crop.html" (
  echo 找不到 kss-crop.html。请确认它和这个 bat 在同一个文件夹里。
  echo.
  pause
  exit /b 1
)
echo 即将打开选图工具。用法：
echo   1. 在网页里点"点击选图"，或用鼠标把图片拖进去。
echo   2. 在左图拖动青色框选区域，选好机型。
echo   3. 点"导出 PNG"，图片会下载到"下载"文件夹。
echo   4. 再把下载好的图片拖到"3-拖图片到这里加屏保.bat"即可。
echo.
start "" "%~dp0kss-crop.html"
