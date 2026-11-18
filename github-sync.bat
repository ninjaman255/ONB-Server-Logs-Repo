
@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==========================================
REM CONFIGURATION
REM ==========================================

set "REPO_URL="https://github.com/ninjaman255/ONB-Server-Logs-Repo"
set "BRANCH=main"

REM Automatically detect the script's directory
set "SOURCE_DIR=%~dp0"

REM Temporary workspace
set "WORK_DIR=%TEMP%\github-sync-%RANDOM%-%RANDOM%"
set "REPO_DIR=%WORK_DIR%\repo"

REM ==========================================
REM CHECK REQUIREMENTS
REM ==========================================

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git for Windows is required.
    goto :fail
)

where robocopy >nul 2>&1
if errorlevel 1 goto :fail

if exist "%WORK_DIR%" goto :fail

mkdir "%WORK_DIR%"
if errorlevel 1 goto :fail

REM ==========================================
REM CLONE REPOSITORY
REM ==========================================

echo Cloning GitHub repository...

git clone --single-branch --branch "%BRANCH%" "%REPO_URL%" "%REPO_DIR%"
if errorlevel 1 goto :fail

REM ==========================================
REM RECURSIVELY COLLECT FILES
REM ==========================================

echo Collecting all files and directories...

robocopy "%SOURCE_DIR%." "%REPO_DIR%" /E /XD .git /XF .env .git /XJ /R:2 /W:1

REM Robocopy codes below 8 indicate success
if errorlevel 8 goto :fail

REM ==========================================
REM COMMIT AND PUSH
REM ==========================================

git -C "%REPO_DIR%" add -A
if errorlevel 1 goto :fail

git -C "%REPO_DIR%" diff --cached --quiet

if not errorlevel 1 goto :no_changes
if errorlevel 2 goto :fail

git -C "%REPO_DIR%" commit -m "Automatic sync %DATE% %TIME%"
if errorlevel 1 goto :fail

git -C "%REPO_DIR%" push origin "%BRANCH%"
if errorlevel 1 goto :fail

echo SUCCESS: Changes pushed to GitHub!
goto :success

:no_changes
echo No changes detected.
goto :success

:success
set "EXIT_CODE=0"
goto :cleanup

:fail
echo ERROR: Synchronization failed.
set "EXIT_CODE=1"
goto :cleanup

:cleanup
if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"
pause
exit /b %EXIT_CODE%
