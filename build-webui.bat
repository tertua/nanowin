@echo off
chcp 65001 >nul 2>&1
title Nanobot WebUI Build

:: Check for PowerShell
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] PowerShell not found in PATH.
    echo  Windows PowerShell 5.1+ is required.
    echo.
    pause
    exit /b 1
)

echo.
echo  This downloads ~250MB node_modules on first run (npm is incremental on re-runs).
echo  Requires internet. Re-runnable for retries.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_webui.ps1"
set "RC=%errorlevel%"

if %RC% neq 0 goto :err

echo.
echo  Build successful.
echo.
pause
exit /b %RC%

:err
echo.
echo  [WARN] Webui build failed, exit %RC%.
echo         setup.bat already completed - retry by running build-webui.bat again.
echo.
pause
exit /b %RC%
