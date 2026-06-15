@echo off
setlocal enabledelayedexpansion

rem ==========================================================
rem  setup.bat - Nanobot Portable Bootstrap (Windows 10/11)
rem  Minimal requirement: Windows 10 version 1809+
rem  Uses built-in Windows PowerShell 5.1
rem ==========================================================

rem --- Root directory (script location) ----------------------
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

cd /d "%ROOT%"

rem --- UTF-8 console ------------------------------------------
chcp 65001 >nul 2>&1

rem --- Early exit if already completed ------------------------
if exist "data\.lockhead" (
    echo.
    echo  [INFO] Setup already completed.
    echo  Delete "data\.lockhead" to re-run setup.
    echo.
    timeout /t 2 /nobreak >nul
    exit /b 0
)

rem --- Banner --------------------------------------------------
echo ============================================================
echo    NANOWIN PORTABLE BUILDER - Visit simata.id
echo ============================================================

TIMEOUT /T 3 /NOBREAK

rem --- Check minimum Windows version ----------------------------
for /f "tokens=2 delims=[]" %%v in ('ver') do (
    for /f "tokens=2" %%a in ("%%v") do (
        for /f "tokens=1 delims=." %%b in ("%%a") do set "WIN_VER=%%b"
    )
)
if not defined WIN_VER set "WIN_VER=0"
if %WIN_VER% LSS 10 (
    echo [ERROR] Windows 10 or later required.
    echo         Your Windows Version: %WIN_VER%
    pause
    exit /b 1
)

rem --- Paths ----------------------------------------------------
set "BIN_DIR=%ROOT%\bin"
set "TMP_DIR=%ROOT%\tmp"
set "SETUP_SCRIPT=%ROOT%\scripts\nanobot-setup.ps1"

rem --- Create temp directory ------------------------------------
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

rem --- Check PowerShell 5.1+ availability -----------------------
echo [INFO] Checking Windows PowerShell...
echo.

for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$PSVersionTable.PSVersion.Major"`) do set "PS_MAJOR=%%a"
if not defined PS_MAJOR (
    echo [ERROR] Windows PowerShell unavailable or damaged.
    echo         Make sure Windows PowerShell 5.1+ is exist.
    pause
    exit /b 1
)
if %PS_MAJOR% LSS 5 (
    echo [ERROR] Windows PowerShell version 5.1+ required.
    echo         Version detected: %PS_MAJOR%.x
    pause
    exit /b 1
)

echo [OK] Windows PowerShell %PS_MAJOR%.x detected.
echo.

rem --- Run main setup ----------------------------------------------
echo ================================================================
echo    Running the lite setup (nanobot-setup.ps1)
echo ================================================================

if not exist "%SETUP_SCRIPT%" (
    echo [ERROR] Setup script not found: %SETUP_SCRIPT%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

echo ================================================================
echo    SETUP FINISHED (Exit Code: %EXIT_CODE%)
echo ================================================================

if %EXIT_CODE% neq 0 (
    echo [WARN] The main setup exits with error code %EXIT_CODE%.
    pause
    exit /b %EXIT_CODE%
)

pause
exit /b 0
