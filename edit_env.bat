@echo off
cd /d "%~dp0"
setlocal EnableDelayedExpansion
title Nanobot Protect .env

set "ROOT=%~dp0"
set "PY=%ROOT%bin\python.exe"
set "PATH=%ROOT%bin;%ROOT%bin\Scripts;%ROOT%bin\nodejs;%ROOT%scripts;%ROOT%data;%PATH%"
set "HOME=%ROOT%data\home"
set "NPM_CONFIG_CACHE=%ROOT%tmp\npm-cache"
set "NPM_CONFIG_PREFIX=%ROOT%bin\nodejs\global"

echo.
echo  ========================================
echo    EDIT API KEY (.env)
echo  ========================================
echo.

if exist "data\.env" goto :decrypt
if exist "data\.env.encrypted" goto :decrypt

if not exist "data\.env.example" (
    echo  [ERROR] No file.
    pause
    exit /b 1
)

copy "data\.env.example" "data\.env" >nul
echo  [OK] .env template created.

:decrypt
if not exist "data\.env.encrypted" (
    echo  [1/3] skip
    goto :edit
)

echo  [1/3] Decrypting...
if exist "data\.env_key" (
    set /p ENV_KEY=<"data\.env_key"
    set "NANOBOT_ENV_KEY=!ENV_KEY!"
    "%PY%" "%ROOT%scripts\env_crypt.py" decrypt --noninteractive
) else (
    "%PY%" "%ROOT%scripts\env_crypt.py" decrypt
)
if errorlevel 1 (
    echo  [ERROR] Failed.
    pause
    exit /b 1
)

:edit
echo  [2/3] Active provider context:
set "HAVE_PROVIDER="
for /f "usebackq tokens=*" %%L in (`powershell -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; $c = Get-Content 'data\config.json' -Raw | ConvertFrom-Json; $p = $c.agents.defaults.provider; if ($p) { Write-Output ('Provider: ' + $p); $pf = $c.providers.$p; if ($pf) { $pf.PSObject.Properties | ForEach-Object { if ($_.Value -match '\$\{([^}]+)\}') { Write-Output ('  uses: ' + $Matches[1]) } } } }"`) do (
    echo         %%L
    set "HAVE_PROVIDER=1"
)
if not defined HAVE_PROVIDER (
    echo         ^^(no provider info; showing all .env keys^^^)
)
echo.
echo  Opening Notepad for editing...
start /wait notepad "data\.env"

echo  [3/3] Re-encryption...
if exist "data\.env_key" (
    set /p ENV_KEY=<"data\.env_key"
    set "NANOBOT_ENV_KEY=!ENV_KEY!"
    "%PY%" "%ROOT%scripts\env_crypt.py" encrypt --noninteractive
) else (
    "%PY%" "%ROOT%scripts\env_crypt.py" encrypt --save-key
)
if errorlevel 1 (
    echo  [ERROR] Failed.
    pause
    exit /b 1
)

echo.
echo  Finished.
pause
