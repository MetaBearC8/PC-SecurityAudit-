@echo off
setlocal
title SecurityAudit Portable Installer v4.2

echo ===============================================
echo SecurityAudit Portable Installer v4.2
echo ===============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Please right-click this BAT file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

set "SRC=%~dp0SecurityAudit-v4.1.ps1"
set "DESTDIR=C:\SecurityAudit"
set "DEST=%DESTDIR%\SecurityAudit.ps1"
set "TASKNAME=Windows Security Audit"
set "STATUSFILE=%DESTDIR%\last_sync_status.txt"

if not exist "%SRC%" (
    echo ERROR: SecurityAudit-v4.1.ps1 was not found beside this BAT file.
    echo.
    pause
    exit /b 1
)

if not exist "%DESTDIR%" mkdir "%DESTDIR%"

echo [1/5] Installing SecurityAudit.ps1...
copy /Y "%SRC%" "%DEST%" >nul
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy SecurityAudit.ps1.
    pause
    exit /b 1
)

if exist "%STATUSFILE%" del /Q "%STATUSFILE%" >nul 2>&1

echo [2/5] Running a test audit and Google Drive sync...
echo This may take a few minutes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DEST%"

echo.
echo [3/5] Verifying Google Drive synchronization...
if not exist "%STATUSFILE%" (
    echo ERROR: Sync status file was not created.
    echo Make sure Google Drive for Desktop is installed and signed in.
    echo Also make sure SecurityAudit Reports is available in My Drive with edit access.
    echo.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath '%STATUSFILE%' -ErrorAction SilentlyContinue; if ($s -match '^STATUS=OK$') { exit 0 } else { exit 1 }"
if %errorlevel% neq 0 (
    echo ERROR: Google Drive synchronization test failed.
    echo.
    type "%STATUSFILE%"
    echo.
    echo Required setup:
    echo 1. Install Google Drive for Desktop.
    echo 2. Sign in to the designated upload account.
    echo 3. Make sure SecurityAudit Reports is under My Drive.
    echo 4. Make sure the account has Editor access.
    echo.
    pause
    exit /b 2
)

echo Google Drive synchronization test: OK

echo [4/5] Creating scheduled task at 08:00 and 20:00...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"$taskName='%TASKNAME%';" ^
"$script='C:\SecurityAudit\SecurityAudit.ps1';" ^
"$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File ""{0}""' -f $script);" ^
"$t1=New-ScheduledTaskTrigger -Daily -At '08:00';" ^
"$t2=New-ScheduledTaskTrigger -Daily -At '20:00';" ^
"$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;" ^
"Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($t1,$t2) -Settings $settings -RunLevel Highest -Description 'Windows SecurityAudit at 08:00 and 20:00.' -Force | Out-Null"

if %errorlevel% neq 0 (
    echo ERROR: Failed to create scheduled task.
    pause
    exit /b 1
)

echo [5/5] Scheduled task status...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"Get-ScheduledTask -TaskName '%TASKNAME%' | Select-Object TaskName,State | Format-Table -AutoSize; Get-ScheduledTaskInfo -TaskName '%TASKNAME%' | Select-Object LastRunTime,LastTaskResult,NextRunTime | Format-List"

echo.
echo ===============================================
echo Installation completed successfully.
echo ===============================================
echo Script   : C:\SecurityAudit\SecurityAudit.ps1
echo Schedule : 08:00 and 20:00 daily
echo Cloud    : Auto-detected Google Drive My Drive

echo.
echo You can now use Run-SecurityAudit-and-ChatGPT-v3.bat for manual scans.
echo.
pause
endlocal
