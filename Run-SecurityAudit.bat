@echo off
setlocal
title SecurityAudit Runner

echo ===============================================
echo SecurityAudit Runner
echo ===============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT=C:\SecurityAudit\SecurityAudit.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: %SCRIPT% not found.
    echo.
    pause
    exit /b 1
)

echo Running SecurityAudit...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%errorlevel%"

echo.
if not "%RC%"=="0" (
    echo ===============================================
    echo SecurityAudit FAILED. Exit code: %RC%
    echo ===============================================
    echo Please copy the error shown above.
    echo.
    pause
    exit /b %RC%
)

echo ===============================================
echo SecurityAudit completed successfully.
echo ===============================================
echo.
pause
endlocal
