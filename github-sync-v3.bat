@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==================================================
REM GITHUB FOLDER SYNC v3 - CONFIGURATION
REM ==================================================
set "REPO_URL=https://github.com/ninjaman255/ONB-Server-Logs-Repo"
set "BRANCH=main"
REM Leave blank for repo root, or set e.g. servers/alpha/logs
REM Only letters, numbers, underscores, dashes, dots, and / are allowed.
set "REPO_SUBDIR="

REM Automatically sync everything in the batch file's folder.
set "SOURCE_DIR=%~dp0"

REM Every source folder has its own optional scheduled task.
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
echo ========== GitHub Sync v3 (Windows) ==========
echo Source: "%SOURCE_DIR%"
echo Destination: "%REPO_SUBDIR%" (blank means repository root)
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
REM --sync runs without opening the menu or pausing.
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

REM Validate before concatenating the destination to a local path.
REM Reject absolute paths, parent traversal and internal Git directories.
:validate_destination
set "DEST_REL_WIN="
if not defined REPO_SUBDIR exit /b 0
if "%REPO_SUBDIR%"=="." exit /b 0
set REPO_SUBDIR | findstr /R /C:"^REPO_SUBDIR=[A-Za-z0-9_./-][A-Za-z0-9_./-]*$" >nul
if errorlevel 1 (
    echo ERROR: REPO_SUBDIR must use only letters, numbers, _, -, . and /.
    exit /b 1
)
if "%REPO_SUBDIR:~0,1%"=="/" (
    echo ERROR: REPO_SUBDIR must be relative to the repository root.
    exit /b 1
)
if "%REPO_SUBDIR:~-1%"=="/" (
    echo ERROR: REPO_SUBDIR must not end in a slash.
    exit /b 1
)
if not "%REPO_SUBDIR://=/%"=="%REPO_SUBDIR%" (
    echo ERROR: REPO_SUBDIR must not contain empty path segments.
    exit /b 1
)
for %%P in (%REPO_SUBDIR:/= %) do (
    if "%%P"=="." (
        echo ERROR: REPO_SUBDIR may not contain . segments.
        exit /b 1
    )
    if "%%P"==".." (
        echo ERROR: REPO_SUBDIR may not contain .. segments.
        exit /b 1
    )
    if /I "%%P"==".git" (
        echo ERROR: REPO_SUBDIR may not contain .git segments.
        exit /b 1
    )
)
set "DEST_REL_WIN=%REPO_SUBDIR:/=\%"
exit /b 0

:sync_now
if "%REPO_URL%"=="https://github.com/USERNAME/REPOSITORY.git" (
    echo ERROR: Set REPO_URL at the top of this script first.
    exit /b 1
)
call :validate_destination
if errorlevel 1 exit /b 1
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

set "DEST_DIR=%REPO_DIR%"
if defined DEST_REL_WIN set "DEST_DIR=%REPO_DIR%\%DEST_REL_WIN%"

echo.
echo Source: "%SOURCE_DIR%"
echo Repository: "%REPO_URL%"
echo Branch: "%BRANCH%"
echo Destination folder: "%DEST_DIR%"
echo Cloning repository...
git clone --quiet --single-branch --branch "%BRANCH%" "%REPO_URL%" "%REPO_DIR%"
if errorlevel 1 goto :sync_failed

if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"
if errorlevel 1 goto :sync_failed

echo Copying files recursively...
REM /E includes all subdirectories; no /MIR or /PURGE preserves remote files.
REM /XD excludes Git folders; /XF excludes .env files.
robocopy "%SOURCE_DIR%." "%DEST_DIR%" /E /XD .git /XF .env /XJ /R:2 /W:1 /NFL /NDL /NP
if errorlevel 8 goto :sync_failed

git -C "%REPO_DIR%" add -A
if errorlevel 1 goto :sync_failed

git -C "%REPO_DIR%" diff --cached --quiet
if not errorlevel 1 goto :sync_no_changes
if errorlevel 2 goto :sync_failed

git -C "%REPO_DIR%" commit -m "Automatic sync %DATE% %TIME%"
if errorlevel 1 goto :sync_failed

REM Other servers may update this repository concurrently.
REM Rebase on the latest remote branch and retry up to three times.
for /L %%A in (1,1,3) do (
    git -C "%REPO_DIR%" push origin "%BRANCH%"
    if not errorlevel 1 goto :sync_success
    if "%%A"=="3" goto :sync_failed
    echo Push rejected - fetching latest changes and retrying...
    git -C "%REPO_DIR%" fetch origin "%BRANCH%"
    if errorlevel 1 goto :sync_failed
    git -C "%REPO_DIR%" rebase "origin/%BRANCH%"
    if errorlevel 1 (
        git -C "%REPO_DIR%" rebase --abort >nul 2>&1
        echo ERROR: Concurrent changes conflict. Resolve manually.
        goto :sync_failed
    )
)
goto :sync_failed

:sync_no_changes
echo No changes to upload.
goto :sync_success

:sync_failed
echo ERROR: Sync failed. Review the output above.
set "SYNC_EXIT=1"
goto :sync_cleanup

:sync_success
echo SUCCESS: Sync complete.
set "SYNC_EXIT=0"

:sync_cleanup
if exist "%WORK_DIR%" rmdir /S /Q "%WORK_DIR%"
exit /b %SYNC_EXIT%

:quit
exit /b 0
