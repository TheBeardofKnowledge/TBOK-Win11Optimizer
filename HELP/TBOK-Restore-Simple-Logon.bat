@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ================================================================
REM TBOK - Restore Default Windows VerboseStatus Behavior
REM ================================================================
REM TBOK sets:
REM
REM HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
REM     VerboseStatus = 1
REM
REM This utility removes that explicit override so Windows can use
REM its default status-message behavior.
REM ================================================================

fltmc.exe >nul 2>&1
if errorlevel 1 goto :RequestElevation

goto :RestoreVerboseStatus


:RequestElevation
echo Requesting administrative elevation...

set "TBOK_RESTORE_SCRIPT=%~f0"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ^
    -NoLogo ^
    -NoProfile ^
    -NonInteractive ^
    -Command ^
    "try {" ^
    "    $p=Start-Process -FilePath $env:TBOK_RESTORE_SCRIPT -Verb RunAs -Wait -PassThru -ErrorAction Stop;" ^
    "    exit [int]$p.ExitCode;" ^
    "} catch {" ^
    "    Write-Error $_.Exception.Message;" ^
    "    exit 1;" ^
    "}"

exit /b %ERRORLEVEL%


:RestoreVerboseStatus
cls

echo ================================================================
echo TBOK - Restore Default Windows VerboseStatus Behavior
echo ================================================================
echo.

set "TBOK_VERBOSE_KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

REG QUERY "%TBOK_VERBOSE_KEY%" /v VerboseStatus /reg:64 >nul 2>&1

if errorlevel 1 (
    echo [OK] VerboseStatus is not explicitly configured.
    echo      Windows is already using its default behavior.
    echo.
    goto :Success
)

echo Removing the TBOK VerboseStatus override...

REG DELETE "%TBOK_VERBOSE_KEY%" ^
    /v VerboseStatus ^
    /f ^
    /reg:64 >nul 2>&1

if errorlevel 1 (
    echo.
    echo [ERROR] VerboseStatus could not be removed.
    echo.
    echo The registry location is:
    echo %TBOK_VERBOSE_KEY%
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

REM Verify that the value is actually absent.
REG QUERY "%TBOK_VERBOSE_KEY%" /v VerboseStatus /reg:64 >nul 2>&1

if not errorlevel 1 (
    echo.
    echo [ERROR] VerboseStatus still exists after the removal attempt.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo [OK] VerboseStatus override was removed successfully.


:Success
echo.
echo ================================================================
echo WINDOWS DEFAULT BEHAVIOR RESTORED
echo ================================================================
echo.
echo Windows will now use its default sign-in, sign-out, startup,
echo shutdown, and policy-processing status-message behavior.
echo.
echo A restart is recommended before evaluating the change.
echo.
echo IMPORTANT:
echo Running the current TBOK optimization again will recreate:
echo.
echo     VerboseStatus = 1
echo.
echo unless that setting is also removed or changed in TBOK itself.
echo.
echo Press any key to close...
pause >nul
exit /b 0