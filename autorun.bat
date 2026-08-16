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

if not exist "%~dp0modules\git-wizard.ps1" (
    echo.
    echo [!] ERROR: Could not locate 'modules\git-wizard.ps1'!
    echo [!] Please verify the repository folder structure.
    echo.
    pause
    exit /b 1
)

:: Verify powershell.exe is actually reachable before trying to launch
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo [!] ERROR: 'powershell.exe' not found on this system!
    echo [!] Install Windows PowerShell or ensure it is on your PATH.
    echo.
    pause
    exit /b 1
)

:: Launch with -NoProfile (skip user profile loading for clean startup)
:: and -NoExit (keep window open after script finishes or errors)
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0modules\git-wizard.ps1"

:: SAFETY NET: If powershell.exe returns here for ANY reason
:: (crash, access denied, syntax error in .ps1, etc.),
:: the window stays open so you can actually read what went wrong.
echo.
echo [!] PowerShell exited unexpectedly. See any error messages above.
echo.
pause
