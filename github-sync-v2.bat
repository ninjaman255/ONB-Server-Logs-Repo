@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==================================================
REM CONFIGURATION - edit these two values
REM ==================================================
set "REPO_URL=https://github.com/USERNAME/REPOSITORY.git"
set "BRANCH=main"

REM Source is always the folder containing this batch file.
set "SOURCE_DIR=%~dp0"

REM Unique task name based on the full source folder path.
set "TASK_NAME=GitHubSync_%SOURCE_DIR:\=_%"
set "TASK_NAME=%TASK_NAME::=%"
set "TASK_NAME=%TASK_NAME: =_%"
set "LOG_DIR=%LOCALAPPDATA%\GitHubSync"
set "LOG_FILE=%LOG_DIR%\%TASK_NAME%.log"

if /I "%~1"=="--sync" goto :scheduled_sync
if /I "%~1"=="--status" goto :status_once
if /I "%~1"=="--remove-schedule" goto :remove_once
if not "%~1"=="" goto :usage

:menu
echo.
echo ========== GitHub Sync (Windows) ==========
echo Source: "%SOURCE_DIR%"
echo 1^) Sync now
echo 2^) Enable/change automatic sync
echo 3^) Disable automatic sync
echo 4^) View schedule status
echo 5^) Exit
choice /C 12345 /N /M "Choice [1-5]: "
if errorlevel 5 goto :quit
if errorlevel 4 goto :menu_status
if errorlevel 3 goto :menu_remove
if errorlevel 2 goto :install_schedule
if errorlevel 1 goto :menu_sync
goto :menu

:menu_sync
call :sync_now
echo.
pause
goto :menu

:menu_status
call :show_status
echo.
pause
goto :menu

:menu_remove
call :remove_schedule
echo.
pause
goto :menu

:install_schedule
echo.
echo Choose how often to sync:
echo 1^) Every 15 minutes
echo 2^) Every 30 minutes
echo 3^) Every hour
echo 4^) Daily at 2:00 AM
echo 5^) Cancel
choice /C 12345 /N /M "Choice [1-5]: "
if errorlevel 5 goto :menu
set "SCHEDULE_TYPE=MINUTE"
set "SCHEDULE_MODIFIER=15"
set "SCHEDULE_START="
if errorlevel 4 goto :frequency_daily
if errorlevel 3 set "SCHEDULE_MODIFIER=60"
if errorlevel 2 if not errorlevel 3 set "SCHEDULE_MODIFIER=30"
goto :create_schedule

:frequency_daily
set "SCHEDULE_TYPE=DAILY"
set "SCHEDULE_MODIFIER=1"
set "SCHEDULE_START=/ST 02:00"

:create_schedule
echo.
echo Registering scheduled task: "%TASK_NAME%"
REM The embedded quotes keep paths containing spaces intact.
REM --sync runs headlessly, without the interactive menu or pause.
schtasks /Create /F /TN "%TASK_NAME%" /TR "\"%~f0\" --sync" /SC %SCHEDULE_TYPE% /MO %SCHEDULE_MODIFIER% %SCHEDULE_START%
if errorlevel 1 (
    echo ERROR: Could not register the scheduled task.
) else (
    echo Automatic sync enabled.
    echo Scheduled log: "%LOG_FILE%"
)
echo.
pause
goto :menu

:show_status
schtasks /Query /TN "%TASK_NAME%" /FO LIST 2>nul
if errorlevel 1 echo No automatic sync is configured for this folder.
echo Log file: "%LOG_FILE%"
exit /b 0

:remove_schedule
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if errorlevel 1 (
    echo No scheduled sync exists for this folder.
    exit /b 0
)
schtasks /Delete /TN "%TASK_NAME%" /F
if errorlevel 1 (
    echo ERROR: Could not delete the scheduled task.
    exit /b 1
)
echo Automatic sync disabled.
exit /b 0

:scheduled_sync
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
call :sync_now >> "%LOG_FILE%" 2>&1
exit /b %errorlevel%

:status_once
call :show_status
exit /b %errorlevel%

:remove_once
call :remove_schedule
exit /b %errorlevel%

:usage
echo Usage: github-sync.bat [--sync ^| --status ^| --remove-schedule]
exit /b 2

:sync_now
if "%REPO_URL%"=="https://github.com/USERNAME/REPOSITORY.git" (
    echo ERROR: Edit REPO_URL at the top of this script first.
    exit /b 1
)
where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Install Git for Windows and ensure git is on PATH.
    exit /b 1
)
where robocopy >nul 2>&1
if errorlevel 1 (
    echo ERROR: robocopy is unavailable.
    exit /b 1
)

set "WORK_DIR=%TEMP%\github-sync-%RANDOM%-%RANDOM%"
set "REPO_DIR=%WORK_DIR%\repo"
if exist "%WORK_DIR%" (
    echo ERROR: Temporary workspace already exists: "%WORK_DIR%"
    exit /b 1
)
mkdir "%WORK_DIR%"
if errorlevel 1 exit /b 1

echo.
echo Source: "%SOURCE_DIR%"
echo Repository: "%REPO_URL%"
echo Branch: "%BRANCH%"
echo Cloning repository...
git clone --quiet --single-branch --branch "%BRANCH%" "%REPO_URL%" "%REPO_DIR%"
if errorlevel 1 goto :sync_failed

echo Copying files recursively...
REM /E includes subdirectories and empty folders.
REM /XD excludes nested .git folders, /XF excludes .env files.
REM No /MIR or /PURGE: repository-only files are preserved.
robocopy "%SOURCE_DIR%." "%REPO_DIR%" /E /XD .git /XF .env /XJ /R:2 /W:1 /NFL /NDL /NP
if errorlevel 8 goto :sync_failed

git -C "%REPO_DIR%" add -A
if errorlevel 1 goto :sync_failed

git -C "%REPO_DIR%" diff --cached --quiet
if not errorlevel 1 goto :sync_no_changes
if errorlevel 2 goto :sync_failed

git -C "%REPO_DIR%" commit -m "Automatic sync %DATE% %TIME%"
if errorlevel 1 goto :sync_failed

git -C "%REPO_DIR%" push origin "%BRANCH%"
if errorlevel 1 goto :sync_failed

echo SUCCESS: Changes pushed to GitHub.
goto :sync_success

:sync_no_changes
echo No changes to upload.
goto :sync_success

:sync_failed
echo ERROR: Sync failed. Review the output above.
set "SYNC_EXIT=1"
goto :sync_cleanup

:sync_success
set "SYNC_EXIT=0"

:sync_cleanup
if exist "%WORK_DIR%" rmdir /S /Q "%WORK_DIR%"
exit /b %SYNC_EXIT%

:quit
exit /b 0
