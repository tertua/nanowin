@echo off
chcp 65001 >nul 2>&1
title Nanobot Gateway

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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nanobot-gateway.ps1"
set "RC=%errorlevel%"

if %RC% neq 0 (
    echo.
    echo  [ERROR] Nanobot exited with code %RC%
    echo  Check setup_log.txt or run setup.bat first.
    echo.
) else (
    echo.
    echo  Nanobot Gateway Stopped.
    echo.
)

pause
exit /b %RC%
