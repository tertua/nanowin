@echo off
chcp 65001 >nul 2>&1
title Nanobot Agent

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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nanobot-agent.ps1"

if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Nanobot exited with code %errorlevel%
    echo  Check setup_log.txt or run setup.bat first.
    echo.
    pause
)

exit /b %errorlevel%
