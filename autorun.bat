@echo off
chcp 65001 >nul
TITLE Git-Wizard Ultimate - Master Launcher (Windows)

:: Lock working directory to autorun.bat folder
cd /d "%~dp0"
cls

echo ====================================================================
echo         [WIZARD] GIT-WIZARD ULTIMATE - MASTER LAUNCHER (WINDOWS)
echo ====================================================================
echo.
echo [i] Launching Git-Wizard PowerShell Core Engine...
echo.

if exist "%~dp0modules\git-wizard.ps1" (
    powershell.exe -NoExit -ExecutionPolicy Bypass -File "%~dp0modules\git-wizard.ps1"
) else (
    echo [!] ERROR: Could not locate 'modules\git-wizard.ps1'!
    echo [!] Please verify the repository folder structure.
    pause
)