:: Hello - if youre reading this its because you dont just blindly apply scripts "willy nilly"
:: You want to know the meat and potatoes of what its doing - NO "TRUST ME BRO" LOGIC
:: I respect that, and honestly, it's the only way you should run a script you didn't make
:: Ive taken the steps to painfully document each section - please read it
:: This script is a combination of my 25 plus years of IT experience with Windows as an IT admin
:: While it is nothing slick or polished - it gets down to the essentials that I believe
:: should be the standard in a Windows Install to function properly without the excess nobody but MS asked for
:: The main issue I had with debloat and optimization scripts is that none of them did this
:: ***Apply the settings to all users of a pc, including future users, and without breaking any useful features***
:: The aim for this is to have a simple script you can either directly run on a pc or push to a machine
:: on the network and have it automatically Optimize the system without you touching anything
:: No GUI, no decision, just every good change that makes Windows run better and leaner all in one go
:: If you don't understand something here, just ask, my DM's and comments on social media are open
:: If you have an issue or want to request a feature, please request it on GitHub
:: If you want to learn more about each command, use what I use learn.microsoft.com
:: READY... Lets go
:: FYI you can now run this script on remote computer using the following switches for a menuless run":
:: /optimize - runs the main routine to optimize and debloat 
:: /cleanup - Agressive disk cleanup using my BeardSweeper script
:: /gaming - apply gaming tweaks 
:: /winget - full auto software update using WinGet
:: /newlog - starts a new log file for the workstation being run on, if not it will reuse existing
:: /restart - restarts the computer after all requested noninteractive operations complete

::turn off echoing all commands
@ECHO OFF
::change the terminal color to something friendlier
color f0

::enable holding variables during script,explicitely enable command extensions, disable variable expansions
setlocal EnableExtensions DisableDelayedExpansion

::Script release version and release date 
:ScriptVersion
set "VERSION=1.6.9"
set "VERDATE=10-16-2026"

:Elevation
:: Automatically check for and obtain administrative elevation, retain working directory, allow special characters in path names
echo No changes are being made at this time.

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not errorlevel 1 goto :GotPrivileges

echo Requesting administrative elevation...

set "ELEVATE_SCRIPT=%~f0"
set "ELEVATE_WORKDIR=%~dp0"
set "ELEVATE_ARGUMENTS=%*"

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $quote = [char]34;" ^
    "    $batchCommand = $quote + $env:ELEVATE_SCRIPT + $quote;" ^
    "    if ($env:ELEVATE_ARGUMENTS) {" ^
    "        $batchCommand += ' ' + $env:ELEVATE_ARGUMENTS;" ^
    "    };" ^
    "    $cmdArguments = '/d /c ' + $quote + $batchCommand + $quote;" ^
    "    Start-Process -FilePath $env:ComSpec -Verb RunAs -WorkingDirectory $env:ELEVATE_WORKDIR -ArgumentList $cmdArguments -ErrorAction Stop;" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Error ('Elevation launch failed: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}"

set "ELEVATE_RC=%ERRORLEVEL%"

set "ELEVATE_SCRIPT="
set "ELEVATE_WORKDIR="
set "ELEVATE_ARGUMENTS="

if not "%ELEVATE_RC%"=="0" (
    echo Elevation was canceled or failed.
    echo This script requires an elevated administrative session.
    echo When using PowerShell remoting, start the session with sufficient administrative rights.
    exit /b 1
)

exit /b 0

:GotPrivileges
ECHO Script elevated successfully
cls

:BEGIN-SCRIPT-HELPERS
::These are items that are called later in the script to perform a function - trims the code size for repeat items
::enable extended script logic and delayed expansion
setlocal enableextensions EnableDelayedExpansion

:LogFile
:: Reuse newest logfile for this computer unless /NEWLOG was specified.
::Log stored in current script directory with computername, date, time stamped info for multi-pc deployments or multi-run
set "TBOK_TIMESTAMP="

for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd-HHmmss"') do (
    set "TBOK_TIMESTAMP=%%A"
)

if not defined TBOK_TIMESTAMP (
    set "TBOK_TIMESTAMP=%RANDOM%-%RANDOM%"
)

set "TBOK_LOG_WAS_CREATED=0"
set "LOGFILE="

:: User explicitly requested a fresh logfile.
if /I not "%~1"=="/NEWLOG" (
    for /f "usebackq delims=" %%L in (`
    dir /b /a-d /o-d "%~dp0TBOKwinOptimizer-%COMPUTERNAME%-*.log" 2^>nul
`) do (
        if not defined LOGFILE (
            set "LOGFILE=%~dp0%%L"
        )
    )
)
if not defined LOGFILE (
    set "LOGFILE=%~dp0TBOKwinOptimizer-%COMPUTERNAME%-!TBOK_TIMESTAMP!.log"
    set "TBOK_LOG_WAS_CREATED=1"
)
if not exist "!LOGFILE!" (
    >"!LOGFILE!" echo([%DATE% %TIME%] TBOK logfile created.
    set "TBOK_LOG_WAS_CREATED=1"
)
if "!TBOK_LOG_WAS_CREATED!"=="0" (
    >>"!LOGFILE!" echo(
    >>"!LOGFILE!" echo([%DATE% %TIME%] ================================================================
    >>"!LOGFILE!" echo([%DATE% %TIME%] Continuing TBOK execution in the existing logfile.
    >>"!LOGFILE!" echo([%DATE% %TIME%] Version %VERSION% %VERDATE%
    >>"!LOGFILE!" echo([%DATE% %TIME%] ================================================================
)
set "TBOK_LOG_WAS_CREATED="

:: Fallback registry backups are created only if restore-point creation fails.
set "TBOK_RESTORE_POINT_FAILED=0"
set "TBOK_PROFILE_BACKUP_DIR="

:: Initialize the consolidated service and scheduled-task queues.
call :InitializeTemporaryPlans

:: Helper labels follow. Skip them during normal top-level execution.
goto :Switches

:Log
::LOG and echo helper to avoid duplicate lines in script - Echoes on screen and also into logfile
::usage call :LOG "message to echo"
setlocal DisableDelayedExpansion
set "LogMessage=%*"
echo(%LogMessage%
>>"%LOGFILE%" echo([%DATE% %TIME%] %LogMessage%
endlocal
exit /b 0

:Switches
set "TBOK_RUN_OPTIMIZE="
set "TBOK_RUN_CLEANUP="
set "TBOK_RUN_GAMING="
set "TBOK_RUN_WINGET="
set "TBOK_RUN_EXIT="
set "TBOK_RUN_RESTART="
set "TBOK_ARGUMENT_ERROR=0"

if "%~1"=="" goto :MENU

:ParseNextArgument
if "%~1"=="" goto :ArgumentsParsed

if /I "%~1"=="/OPTIMIZE" (
    set "TBOK_RUN_OPTIMIZE=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/CLEANUP" (
    set "TBOK_RUN_CLEANUP=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/GAMING" (
    set "TBOK_RUN_GAMING=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/WINGET" (
    set "TBOK_RUN_WINGET=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/RESTART" (
    set "TBOK_RUN_RESTART=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/EXIT" (
    set "TBOK_RUN_EXIT=1"
    shift
    goto :ParseNextArgument
)
if /I "%~1"=="/NEWLOG" (
    shift
    goto :ParseNextArgument
)
call :LOG ERROR: Unknown command-line option: %~1
set "TBOK_ARGUMENT_ERROR=1"
shift
goto :ParseNextArgument

:ArgumentsParsed
if "!TBOK_ARGUMENT_ERROR!"=="1" (
    call :LOG ERROR: The requested command-line sequence was not started because one or more options were invalid.
    goto :EXIT
)
if defined TBOK_RUN_EXIT (
    if defined TBOK_RUN_OPTIMIZE (
        call :LOG ERROR: /EXIT cannot be combined with operation switches.
        goto :EXIT
    )
    if defined TBOK_RUN_CLEANUP (
        call :LOG ERROR: /EXIT cannot be combined with operation switches.
        goto :EXIT
    )
    if defined TBOK_RUN_GAMING (
        call :LOG ERROR: /EXIT cannot be combined with operation switches.
        goto :EXIT
    )
    if defined TBOK_RUN_WINGET (
        call :LOG ERROR: /EXIT cannot be combined with operation switches.
        goto :EXIT
    )
    goto :EXIT
)
if defined TBOK_RUN_OPTIMIZE goto :NonInteractiveSequence
if defined TBOK_RUN_CLEANUP goto :NonInteractiveSequence
if defined TBOK_RUN_GAMING goto :NonInteractiveSequence
if defined TBOK_RUN_WINGET goto :NonInteractiveSequence
goto :MENU


:PrepareRollbackProtection
call :LOG Before anything is modified - creating a system restore point.
call :LOG Ensuring System Restore is enabled on %SystemDrive%...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop; exit 0 } catch { Write-Output ('ERROR: ' + $_.Exception.Message); exit 1 }" ^
    >>"%LOGFILE%" 2>&1

set "RestoreEnableRC=!ERRORLEVEL!"
if not "!RestoreEnableRC!"=="0" (
    call :LOG WARNING: System Restore could not be enabled.
) else (
    call :LOG System Restore enablement command completed successfully.
)

call :LOG Checking restore-point support services...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    foreach ($serviceName in 'VSS','swprv') {" ^
    "        $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter ('Name=''' + $serviceName + '''') -ErrorAction Stop;" ^
    "        if ($null -eq $serviceInfo) {" ^
    "            throw ($serviceName + ' service was not found.');" ^
    "        };" ^
    "        Write-Output ($serviceName + ': State=' + $serviceInfo.State + '; StartMode=' + $serviceInfo.StartMode);" ^
    "        if ($serviceInfo.StartMode -eq 'Disabled') {" ^
    "            Write-Output ('Changing ' + $serviceName + ' from Disabled to Manual...');" ^
    "            $scOutput = @(& sc.exe config $serviceName start= demand 2>&1);" ^
    "            $scRC = $LASTEXITCODE;" ^
    "            $scOutput | ForEach-Object { Write-Output $_ };" ^
    "            if ($scRC -ne 0) {" ^
    "                throw ('sc.exe config failed for ' + $serviceName + ' with exit code ' + $scRC);" ^
    "            };" ^
    "        };" ^
    "    };" ^
    "    $vss = Get-Service -Name VSS -ErrorAction Stop;" ^
    "    if ($vss.Status -ne 'Running') {" ^
    "        Write-Output 'Starting Volume Shadow Copy service...';" ^
    "        Start-Service -Name VSS -ErrorAction Stop;" ^
    "        $vss.WaitForStatus('Running', (New-TimeSpan -Seconds 15));" ^
    "    };" ^
    "    Write-Output 'Restore-point support services are prepared.';" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

set "VssRC=!ERRORLEVEL!"
if not "!VssRC!"=="0" (
    call :LOG WARNING: Volume Shadow Copy service could not be prepared.
)

call :LOG Setting restore-point creation frequency override...
set "RestoreFrequencyExisted=0"
set "RestoreFrequencyValue="

for /f "tokens=3" %%A in ('REG query "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency 2^>nul ^| findstr /I "SystemRestorePointCreationFrequency"') do (
    set "RestoreFrequencyExisted=1"
    set "RestoreFrequencyValue=%%A"
)
REG add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
    /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f ^
    >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG WARNING: Could not set SystemRestorePointCreationFrequency.
)
call :LOG Creating restore point...
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    Checkpoint-Computer -Description 'System Before TBOK Windows Optimizer' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop;" ^
    "    Write-Output 'Restore point command completed successfully.';" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    Write-Output ('Exception type: ' + $_.Exception.GetType().FullName);" ^
    "    Write-Output ('Fully qualified error: ' + $_.FullyQualifiedErrorId);" ^
    "    Write-Output ('Category: ' + $_.CategoryInfo);" ^
    "    if ($_.InvocationInfo) {" ^
    "        Write-Output ('Command: ' + $_.InvocationInfo.MyCommand);" ^
    "        Write-Output ('Position: ' + $_.InvocationInfo.PositionMessage);" ^
    "    };" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

set "RestorePointRC=!ERRORLEVEL!"

call :RestorePointFrequency
set "RestoreFrequencyRC=!ERRORLEVEL!"

if not "!RestoreFrequencyRC!"=="0" (
    call :LOG WARNING: Restore-point creation frequency cleanup did not complete successfully.
)
if "!RestorePointRC!"=="0" (
    set "TBOK_RESTORE_POINT_FAILED=0"
    call :LOG Restore point created successfully.
    exit /b 0
)
set "TBOK_RESTORE_POINT_FAILED=1"
set "TBOK_PROFILE_BACKUP_DIR=%~dp0TBOK-RegistryBackups-%COMPUTERNAME%-!TBOK_TIMESTAMP!"
call :LOG WARNING: Could not create a restore point.
call :LOG Creating fallback registry backup directory...

if not exist "!TBOK_PROFILE_BACKUP_DIR!" (
    mkdir "!TBOK_PROFILE_BACKUP_DIR!" >nul 2>&1
)
if not exist "!TBOK_PROFILE_BACKUP_DIR!" (
    call :LOG CRITICAL: Fallback registry backup directory could not be created.
    set "TBOK_PROFILE_BACKUP_DIR="
) else (
    call :LOG Fallback registry backup directory: !TBOK_PROFILE_BACKUP_DIR!
)
:RestorePointDiagnostics
call :LOG Collecting restore-point diagnostics...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$diagnosticFailure = $false;" ^
    "Write-Output 'Checkpoint-Computer environment:';" ^
    "try {" ^
    "    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop;" ^
    "    Write-Output ('SystemDrive=' + $env:SystemDrive);" ^
    "    Write-Output ('OSVersion=' + $operatingSystem.Version);" ^
    "    Write-Output ('OSBuild=' + $operatingSystem.BuildNumber);" ^
    "    Write-Output ('PowerShellVersion=' + $PSVersionTable.PSVersion.ToString());" ^
    "} catch {" ^
    "    Write-Output ('WARNING: Environment query failed: ' + $_.Exception.Message);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "Write-Output 'System Restore provider status:';" ^
    "try {" ^
    "    $config = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestoreConfig -ErrorAction Stop;" ^
    "    if ($null -eq $config) {" ^
    "        Write-Output 'WARNING: SystemRestoreConfig returned no data.';" ^
    "        $diagnosticFailure = $true;" ^
    "    } else {" ^
    "        Write-Output ('DiskPercent=' + $config.DiskPercent);" ^
    "        Write-Output ('RPSessionInterval=' + $config.RPSessionInterval);" ^
    "    };" ^
    "} catch {" ^
    "    Write-Output ('WARNING: SystemRestoreConfig query failed: ' + $_.Exception.Message);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "Write-Output 'Restore-related service status:';" ^
    "foreach ($serviceName in @('Schedule','EventSystem','COMSysApp','VSS','swprv')) {" ^
    "    try {" ^
    "        $service = Get-Service -Name $serviceName -ErrorAction Stop;" ^
    "        Write-Output ($serviceName + ': Status=' + $service.Status + '; StartType=' + $service.StartType);" ^
    "    } catch {" ^
    "        Write-Output ('WARNING: Could not query service ' + $serviceName + ': ' + $_.Exception.Message);" ^
    "        $diagnosticFailure = $true;" ^
    "    };" ^
    "};" ^
    "Write-Output 'Legacy System Restore service status:';" ^
    "try {" ^
    "    $srService = Get-Service -Name srservice -ErrorAction Stop;" ^
    "    Write-Output ('srservice: Status=' + $srService.Status + '; StartType=' + $srService.StartType);" ^
    "} catch {" ^
    "    Write-Output 'NOTICE: The legacy srservice service is not installed or could not be queried.';" ^
    "};" ^
    "Write-Output 'Existing restore points:';" ^
    "try {" ^
    "    $restorePoints = @(Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -First 5 SequenceNumber,Description,CreationTime);" ^
    "    if ($restorePoints.Count -eq 0) {" ^
    "        Write-Output 'No existing restore points were returned.';" ^
    "    } else {" ^
    "        $restorePoints | Format-Table -AutoSize;" ^
    "    };" ^
    "} catch {" ^
    "    Write-Output ('WARNING: Restore-point enumeration failed: ' + $_.Exception.Message);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "Write-Output 'Shadow storage:';" ^
    "$shadowOutput = @(& vssadmin.exe list shadowstorage 2>&1);" ^
    "$shadowRC = $LASTEXITCODE;" ^
    "$shadowOutput | ForEach-Object { Write-Output $_ };" ^
    "if ($shadowRC -ne 0) {" ^
    "    Write-Output ('WARNING: vssadmin shadowstorage returned exit code ' + $shadowRC);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "Write-Output 'VSS writers:';" ^
    "$writerOutput = @(& vssadmin.exe list writers 2>&1);" ^
    "$writerRC = $LASTEXITCODE;" ^
    "$writerOutput | ForEach-Object { Write-Output $_ };" ^
    "if ($writerRC -ne 0) {" ^
    "    Write-Output ('WARNING: vssadmin writers returned exit code ' + $writerRC);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "if ($diagnosticFailure) { exit 1 } else { exit 0 }" ^
    >>"%LOGFILE%" 2>&1

set "RestoreDiagRC=!ERRORLEVEL!"

if not "!RestoreDiagRC!"=="0" (
    call :LOG WARNING: One or more restore-point diagnostic queries failed. Review the preceding log output.
) else (
    call :LOG Restore-point diagnostics completed successfully.
)

call :LOG Creating HKLM and HKCU registry exports as a fallback...
:: Export every currently loaded user hive for fallback protection.
set "HKLMBackupRC=1"
set "HKCUBackupRC=1"
set "LoadedHiveBackupRC=1"
set "LoadedHiveAttempted=0"
set "LoadedHiveSucceeded=0"
set "LoadedHiveFailed=0"

if defined TBOK_PROFILE_BACKUP_DIR (
    REG export HKLM ^
        "!TBOK_PROFILE_BACKUP_DIR!\HKLM-Before-TBOK.reg" ^
        /y >>"%LOGFILE%" 2>&1

    set "HKLMBackupRC=!ERRORLEVEL!"

    REG export HKCU ^
        "!TBOK_PROFILE_BACKUP_DIR!\HKCU-ExecutionAccount-Before-TBOK.reg" ^
        /y >>"%LOGFILE%" 2>&1

    set "HKCUBackupRC=!ERRORLEVEL!"
    set "LoadedHiveBackupRC=0"

for /f "delims=" %%U in ('REG query HKEY_USERS 2^>nul ^| findstr /B /I /L /C:"HKEY_USERS\S-1-5-21-" /C:"HKEY_USERS\S-1-12-1-" ^| findstr /V /I /C:"_Classes"') do (
        set /a "LoadedHiveAttempted+=1"

        set "LoadedHiveName=%%U"
        set "LoadedHiveFile=!LoadedHiveName:HKEY_USERS\=!"
        set "LoadedHiveFile=!LoadedHiveFile:\=-!"

        REG export "%%U" ^
            "!TBOK_PROFILE_BACKUP_DIR!\HKU-!LoadedHiveFile!-Before-TBOK.reg" ^
            /y >>"%LOGFILE%" 2>&1
        if errorlevel 1 (
            set /a "LoadedHiveFailed+=1"
            set "LoadedHiveBackupRC=1"
            call :LOG ERROR: Failed to export loaded user hive %%U.
        ) else (
            set /a "LoadedHiveSucceeded+=1"
            call :LOG Exported loaded user hive %%U.
        )
    )
) else (
    call :LOG CRITICAL: HKLM, HKCU, and loaded-user registry exports were skipped because the fallback backup directory is unavailable.
)

if "!LoadedHiveAttempted!"=="0" (
    call :LOG NOTICE: No loaded user SID hives were found for fallback export.
) else (
    call :LOG Loaded user hive export summary:
    call :LOG Hives attempted: !LoadedHiveAttempted!
    call :LOG Hives exported successfully: !LoadedHiveSucceeded!
    call :LOG Hives failed: !LoadedHiveFailed!
)
if "!HKLMBackupRC!"=="0" (
    call :LOG HKLM registry export completed successfully.
) else (
    call :LOG ERROR: HKLM registry export failed with exit code !HKLMBackupRC!.
)
if "!HKCUBackupRC!"=="0" (
    call :LOG HKCU registry export completed successfully.
) else (
    call :LOG ERROR: HKCU registry export failed with exit code !HKCUBackupRC!.
)
if not "!HKLMBackupRC!!HKCUBackupRC!!LoadedHiveBackupRC!"=="000" (
    call :LOG CRITICAL: Restore-point creation failed and one or more registry exports also failed.
    call :LOG CRITICAL: A complete rollback-protection method could not be created.
    exit /b 2
)

call :LOG Machine and currently loaded user registry fallback exports completed successfully.
call :LOG Offline and Default profile hive backups will be created during per-user processing.
exit /b 1

::referrence return code results list
::0 = Restore point created successfully
::1 = Restore point failed, but both fallback exports succeeded
::2 = Restore point failed and fallback protection is incomplete

:RequireRollbackProtection
:: helper to retain rollback return codes instead of verifying each time
set "ProtectedOperation=%~1"

if not defined ProtectedOperation (
    set "ProtectedOperation=Requested optimization"
)
if defined TBOK_ROLLBACK_ALREADY_VERIFIED (
    call :LOG Rollback protection was already verified during this session.
    call :LOG Reusing the existing restore-point and registry-backup state.
    exit /b 0
)
set "TBOK_BACKUPS_ALREADY_EXIST=0"
set "TBOK_TODAY="

for /f "delims=" %%A in (
    'powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd"'
) do (
    set "TBOK_TODAY=%%A"
)

for /d %%D in ("%~dp0TBOK-RegistryBackups-%COMPUTERNAME%-*") do (
    echo(%%~nxD | findstr /C:"!TBOK_TODAY!" >nul

    if not errorlevel 1 (
        set "TBOK_BACKUPS_ALREADY_EXIST=1"
    )
)

if "!TBOK_BACKUPS_ALREADY_EXIST!"=="1" (
    call :LOG Rollback backup directory from today was already found.
    call :LOG Skipping restore-point creation and registry-export generation.
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    exit /b 0
)

set "TBOK_BACKUPS_ALREADY_EXIST="
set "TBOK_TODAY="
call :PrepareRollbackProtection
set "RollbackRC=!ERRORLEVEL!"
if "!RollbackRC!"=="0" (
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    exit /b 0
)
if "!RollbackRC!"=="1" (
    call :LOG NOTICE: The restore point failed, but fallback registry exports were created.
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    exit /b 0
)
call :LOG CRITICAL: Complete rollback protection could not be created.
call :LOG CRITICAL: !ProtectedOperation! will not be applied.
exit /b 1

:: Restore the original SystemRestorePointCreationFrequency value.
:RestorePointFrequency
setlocal DisableDelayedExpansion
call :LOG Restoring previous restore point frequency setting

if "%RestoreFrequencyExisted%"=="1" (
    REG ADD "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
        /v SystemRestorePointCreationFrequency /t REG_DWORD ^
        /d "%RestoreFrequencyValue%" /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 (
        endlocal
        call :LOG WARNING: Could not restore the previous SystemRestorePointCreationFrequency value.
        exit /b 1
    )
    endlocal
    call :LOG Restored the previous SystemRestorePointCreationFrequency value.
    exit /b 0
)
REG delete "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
    /v SystemRestorePointCreationFrequency /f >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    endlocal
    call :LOG WARNING: Could not remove the temporary SystemRestorePointCreationFrequency override.
    exit /b 1
)
endlocal
call :LOG Removed the temporary SystemRestorePointCreationFrequency override.
exit /b 0

:AuditStartupItems
call :LOG ================================================================
call :LOG STARTUP AUDIT - Logging startup items
call :LOG ================================================================

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue);" ^
    "if ($startup.Count -eq 0) {" ^
    "    Write-Output 'No startup commands were returned.';" ^
    "} else {" ^
    "    $startup | Sort-Object Location,Name | Format-Table Name,Location,User,Command -AutoSize;" ^
    "}" >>"%LOGFILE%" 2>&1

call :LOG Startup-item audit completed. Review the log before disabling third-party entries.
exit /b 0

::This line is called to modify a service startup mode
:SetServiceStartup
setlocal DisableDelayedExpansion
set "TBOK_SERVICE=%~1"
set "TBOK_STARTMODE=%~2"

if not defined TBOK_SERVICE (
    endlocal
    call :LOG ERROR: SetServiceStartup called without a service name.
    exit /b 2
)
if /i not "%TBOK_STARTMODE%"=="auto" if /i not "%TBOK_STARTMODE%"=="delayed-auto" ^
if /i not "%TBOK_STARTMODE%"=="demand" if /i not "%TBOK_STARTMODE%"=="disabled" (
    endlocal
    call :LOG ERROR: Invalid startup mode "%~2" for service "%~1".
    exit /b 2
)
if not defined TBOK_SERVICE_PLAN (
    endlocal
    call :LOG ERROR: Service startup plan file has not been initialized.
    exit /b 3
)
:: Store one request per line using a pipe delimiter.
>>"%TBOK_SERVICE_PLAN%" echo(%TBOK_SERVICE%^|%TBOK_STARTMODE%

if errorlevel 1 (
    endlocal
    call :LOG ERROR: Failed to queue startup mode "%~2" for service "%~1".
    exit /b 1
)
endlocal
exit /b 0

::This section is used to queue service mode changes in order to run them in a single powershell session for all
::This performs the function much faster while not losing any logging or console output
:: Apply queued service startup changes in one PowerShell session.
:ApplyServiceStartupPlan
setlocal DisableDelayedExpansion

if not defined TBOK_SERVICE_PLAN (
    endlocal
    call :LOG ERROR: Service startup plan file has not been initialized.
    exit /b 3
)
if not exist "%TBOK_SERVICE_PLAN%" (
    endlocal
    call :LOG No service startup changes were queued.
    exit /b 0
)
for %%F in ("%TBOK_SERVICE_PLAN%") do set "TBOK_PLAN_SIZE=%%~zF"

if "%TBOK_PLAN_SIZE%"=="0" (
    del /q "%TBOK_SERVICE_PLAN%" >nul 2>&1
    endlocal
    call :LOG No service startup changes were queued.
    exit /b 0
)
call :LOG Applying queued service startup changes in one PowerShell session...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$planPath = $env:TBOK_SERVICE_PLAN;" ^
    "$requests = @(Get-Content -LiteralPath $planPath -ErrorAction Stop);" ^
	"    $allServiceInfo = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop);" ^
	"    $serviceInfoByName = @{};" ^
	"    foreach ($item in $allServiceInfo) {" ^
	"        $serviceInfoByName[$item.Name.ToLowerInvariant()] = $item;" ^
	"    };" ^
    "$requestCount = 0;" ^
    "$matchedCount = 0;" ^
    "$changedCount = 0;" ^
    "$alreadyConfiguredCount = 0;" ^
    "$preservedDisabledCount = 0;" ^
    "$notInstalledCount = 0;" ^
    "$duplicateCount = 0;" ^
    "$failureCount = 0;" ^
    "$configured = @{};" ^
    "foreach ($line in $requests) {" ^
    "    if ($null -eq $line -or $line.Trim().Length -eq 0) { continue };" ^
    "    $parts = $line.Split('|', 2);" ^
    "    if ($parts.Count -ne 2) {" ^
    "        Write-Output ('FAILED: Invalid service-plan entry: ' + $line);" ^
    "        $failureCount++;" ^
    "        continue;" ^
    "    };" ^
    "    $pattern = $parts[0].Trim();" ^
    "    $requestedMode = $parts[1].Trim().ToLowerInvariant();" ^
    "    $requestCount++;" ^
    "    if ($requestedMode -notin @('auto','delayed-auto','demand','disabled')) {" ^
    "        Write-Output ('FAILED: Invalid startup mode ' + $requestedMode + ' for ' + $pattern);" ^
    "        $failureCount++;" ^
    "        continue;" ^
    "    };" ^
    "    $services = @(Get-Service -Name $pattern -ErrorAction SilentlyContinue);" ^
    "    if ($services.Count -eq 0) {" ^
    "        Write-Output ('NOT INSTALLED: ' + $pattern);" ^
    "        $notInstalledCount++;" ^
    "        continue;" ^
    "    };" ^
    "    foreach ($service in $services) {" ^
    "        $matchedCount++;" ^
    "        $key = $service.Name.ToLowerInvariant();" ^
    "        if ($configured.ContainsKey($key) -and $configured[$key] -eq $requestedMode) {" ^
    "            Write-Output ('DUPLICATE: ' + $service.DisplayName + ' [' + $service.Name + '] already requested as ' + $requestedMode);" ^
    "            $duplicateCount++;" ^
    "            continue;" ^
    "        };" ^
    "        if ($configured.ContainsKey($key)) {" ^
    "            Write-Output ('NOTICE: Re-evaluating ' + $service.Name + ' for requested mode ' + $requestedMode);" ^
    "        };" ^
    "        try {" ^
    "            $serviceInfo = $serviceInfoByName[$key];" ^
    "            if ($null -eq $serviceInfo) {" ^
    "                throw ('Win32_Service metadata was not found for ' + $service.Name);" ^
    "            };" ^
    "            $currentMode = switch ($serviceInfo.StartMode) {" ^
    "                'Auto' { 'auto' }" ^
    "                'Manual' { 'demand' }" ^
    "                'Disabled' { 'disabled' }" ^
    "                default { ([string]$serviceInfo.StartMode).ToLowerInvariant() }" ^
    "            };" ^
    "            if ($currentMode -eq 'auto') {" ^
    "                $serviceRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\' + $service.Name;" ^
    "                $delayedAutoStart = 0;" ^
    "                try {" ^
    "                    $delayedAutoStart = Get-ItemPropertyValue -LiteralPath $serviceRegistryPath -Name DelayedAutoStart -ErrorAction Stop;" ^
    "                } catch {" ^
    "                    $delayedAutoStart = 0;" ^
    "                };" ^
    "                if ($delayedAutoStart -eq 1) {" ^
    "                    $currentMode = 'delayed-auto';" ^
    "                };" ^
    "            };" ^
    "            if ($currentMode -eq 'disabled' -and $requestedMode -eq 'demand') {" ^
    "                Write-Output ('PRESERVED DISABLED: ' + $service.DisplayName + ' [' + $service.Name + '] remained disabled; requested mode was demand');" ^
    "                $configured[$key] = 'disabled';" ^
    "                $preservedDisabledCount++;" ^
    "                continue;" ^
    "            };" ^
    "            if ($currentMode -eq $requestedMode) {" ^
    "                Write-Output ('ALREADY CONFIGURED: ' + $service.DisplayName + ' [' + $service.Name + '] is already ' + $requestedMode);" ^
    "                $configured[$key] = $requestedMode;" ^
    "                $alreadyConfiguredCount++;" ^
    "                continue;" ^
    "            };" ^
    "            Write-Output ('CHANGING: ' + $service.DisplayName + ' [' + $service.Name + '] from ' + $currentMode + ' to ' + $requestedMode);" ^
    "            $scOutput = @(& sc.exe config $service.Name start= $requestedMode 2>&1);" ^
    "            $scRC = $LASTEXITCODE;" ^
    "            $scOutput | ForEach-Object { Write-Output ('  ' + $_) };" ^
    "            if ($scRC -eq 0) {" ^
    "                Write-Output ('CHANGED: ' + $service.DisplayName + ' [' + $service.Name + '] from ' + $currentMode + ' to ' + $requestedMode);" ^
    "                $configured[$key] = $requestedMode;" ^
    "                $changedCount++;" ^
    "            } else {" ^
    "                Write-Output ('FAILED: ' + $service.DisplayName + ' [' + $service.Name + '] from ' + $currentMode + ' to ' + $requestedMode + '; Exit code: ' + $scRC);" ^
    "                $failureCount++;" ^
    "            };" ^
    "        } catch {" ^
    "            Write-Output ('FAILED: Could not evaluate or configure ' + $service.DisplayName + ' [' + $service.Name + ']: ' + $_.Exception.Message);" ^
    "            $failureCount++;" ^
    "        };" ^
    "    };" ^
    "};" ^
    "Write-Output '';" ^
    "Write-Output 'Service startup plan summary:';" ^
    "Write-Output ('  Requests: ' + $requestCount);" ^
    "Write-Output ('  Installed services matched: ' + $matchedCount);" ^
    "Write-Output ('  Changed: ' + $changedCount);" ^
    "Write-Output ('  Already configured: ' + $alreadyConfiguredCount);" ^
    "Write-Output ('  Preserved disabled: ' + $preservedDisabledCount);" ^
    "Write-Output ('  Not installed: ' + $notInstalledCount);" ^
    "Write-Output ('  Duplicate requests: ' + $duplicateCount);" ^
    "Write-Output ('  Failed: ' + $failureCount);" ^
    "if ($failureCount -gt 0) { exit 1 } else { exit 0 }" ^
    >>"%LOGFILE%" 2>&1

set "ServicePlanRC=%ERRORLEVEL%"

if exist "%TBOK_SERVICE_PLAN%" (
    del /q "%TBOK_SERVICE_PLAN%" >nul 2>&1
)
if not "%ServicePlanRC%"=="0" (
    endlocal
    call :LOG WARNING: One or more service startup changes failed.
    exit /b 1
)
endlocal
call :LOG All queued service startup changes completed successfully.
exit /b 0

:: Queue a scheduled task for disabling.
:: Usage: call :DisableTask "\Task\Folder\" "TaskName"
:DisableTask
setlocal DisableDelayedExpansion
set "TaskPath=%~1"
set "TaskName=%~2"

if not defined TaskPath (
    endlocal
    call :LOG ERROR: DisableTask called without a task path.
    exit /b 2
)
if not defined TaskName (
    endlocal
    call :LOG ERROR: DisableTask called without a task name.
    exit /b 2
)
if not defined TBOK_TASK_PLAN (
    endlocal
    call :LOG ERROR: Scheduled-task plan file has not been initialized.
    exit /b 3
)
>>"%TBOK_TASK_PLAN%" echo(%TaskPath%^|%TaskName%
if errorlevel 1 (
    endlocal
    call :LOG ERROR: Failed to queue scheduled task "%~1%~2".
    exit /b 1
)
endlocal
exit /b 0

:: Apply queued scheduled-task changes in one PowerShell session.
:ApplyTaskPlan
setlocal DisableDelayedExpansion

if not defined TBOK_TASK_PLAN (
    endlocal
    call :LOG ERROR: Scheduled-task plan file has not been initialized.
    exit /b 3
)
if not exist "%TBOK_TASK_PLAN%" (
    endlocal
    call :LOG No scheduled tasks were queued.
    exit /b 0
)
for %%F in ("%TBOK_TASK_PLAN%") do set "TBOK_TASK_PLAN_SIZE=%%~zF"

if "%TBOK_TASK_PLAN_SIZE%"=="0" (
    del /q "%TBOK_TASK_PLAN%" >nul 2>&1
    endlocal
    call :LOG No scheduled tasks were queued.
    exit /b 0
)
call :LOG Applying scheduled-task changes in one PowerShell session...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$failed = $false;" ^
    "$lines = @(Get-Content -LiteralPath $env:TBOK_TASK_PLAN -ErrorAction Stop);" ^
    "$installedTasks = @(Get-ScheduledTask -ErrorAction Stop);" ^
    "foreach ($line in $lines) {" ^
    "    if ($null -eq $line -or $line.Trim().Length -eq 0) { continue };" ^
    "    $parts = $line.Split('|', 2);" ^
    "    if ($parts.Count -ne 2) {" ^
    "        Write-Output ('ERROR: Invalid task plan entry: ' + $line);" ^
    "        $failed = $true;" ^
    "        continue;" ^
    "    };" ^
    "    $path = $parts[0].Trim();" ^
    "    $name = $parts[1].Trim();" ^
    "    $tasks = @($installedTasks | Where-Object { $_.TaskPath -eq $path -and $_.TaskName -eq $name });" ^
    "    if ($tasks.Count -eq 0) {" ^
    "        Write-Output ('SKIPPED: Task not found: ' + $path + $name);" ^
    "        continue;" ^
    "    };" ^
    "    foreach ($task in $tasks) {" ^
    "        try {" ^
    "            if ($task.State -eq 'Disabled') {" ^
    "                Write-Output ('SKIPPED: Task already disabled: ' + $task.TaskPath + $task.TaskName);" ^
    "            } else {" ^
    "                $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null;" ^
    "                Write-Output ('SUCCESS: Disabled task: ' + $task.TaskPath + $task.TaskName);" ^
    "            };" ^
    "        } catch {" ^
    "            Write-Output ('ERROR: Failed to disable ' + $task.TaskPath + $task.TaskName + ': ' + $_.Exception.Message);" ^
    "            $failed = $true;" ^
    "        };" ^
    "    };" ^
    "};" ^
    "if ($failed) { exit 1 } else { exit 0 }" >>"%LOGFILE%" 2>&1

set "TaskPlanRC=%ERRORLEVEL%"

if exist "%TBOK_TASK_PLAN%" (
    del /q "%TBOK_TASK_PLAN%" >nul 2>&1
)
endlocal & exit /b %TaskPlanRC%


:RemoveAppxPattern
:: Helper for installed Appx package removal.
:: Removes installed Appx packages matching a package name pattern.
:: Usage: call :RemoveAppxPattern "PackagePattern" "Friendly description"
:: Return codes:
:: 0 = All-user enumeration/removal completed successfully
:: 1 = One or more package queries or removals failed
:: 2 = All-user enumeration was unavailable; SID fallback succeeded
:: 3 = Invalid argument
setlocal DisableDelayedExpansion

set "TBOK_APPX_PATTERN=%~1"
set "TBOK_APPX_LABEL=%~2"

if not defined TBOK_APPX_PATTERN (
    endlocal
    call :LOG ERROR: RemoveAppxPattern called without a package pattern.
    exit /b 3
)

if not defined TBOK_APPX_LABEL (
    set "TBOK_APPX_LABEL=%TBOK_APPX_PATTERN%"
)

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$pattern = $env:TBOK_APPX_PATTERN;" ^
    "$label = $env:TBOK_APPX_LABEL;" ^
    "$allUsersAvailable = ($env:TBOK_APPX_ALLUSERS_UNAVAILABLE -ne '1');" ^
    "$usedPerUserFallback = (-not $allUsersAvailable);" ^
    "$attempted = 0;" ^
    "$removed = 0;" ^
    "$failed = 0;" ^
    "if (-not $allUsersAvailable) {" ^
    "    Write-Output ('NOTICE: All-user Appx enumeration was previously found unavailable for this session. Using per-profile SID fallback for ' + $label + '.');" ^
    "};" ^
    "if ($allUsersAvailable) {" ^
    "    try {" ^
    "        if ($env:TBOK_APPX_INVENTORY -and (Test-Path -LiteralPath $env:TBOK_APPX_INVENTORY)) {" ^
    "            $packages = @(" ^
    "                Get-Content -LiteralPath $env:TBOK_APPX_INVENTORY -ErrorAction Stop |" ^
    "                    ForEach-Object {" ^
    "                        $parts = $_.Split('|', 2);" ^
    "                        if ($parts.Count -eq 2 -and $parts[0] -like $pattern) {" ^
    "                            [PSCustomObject]@{" ^
    "                                Name = $parts[0];" ^
    "                                PackageFullName = $parts[1]" ^
    "                            };" ^
    "                        };" ^
    "                    }" ^
    "            );" ^
    "        } else {" ^
    "            $packages = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Stop);" ^
    "        };" ^
    "        foreach ($package in $packages) {" ^
    "            $attempted++;" ^
    "            try {" ^
    "                Write-Output ('Removing installed package for all users: ' + $package.PackageFullName);" ^
    "                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop;" ^
    "                Write-Output ('SUCCESS: Removed installed package for all users: ' + $package.PackageFullName);" ^
    "                $removed++;" ^
    "            } catch {" ^
    "                Write-Output ('ERROR: Failed all-user removal of ' + $package.PackageFullName + ': ' + $_.Exception.Message);" ^
    "                $failed++;" ^
    "            };" ^
    "        };" ^
    "    } catch {" ^
    "        $allUsersAvailable = $false;" ^
    "        $usedPerUserFallback = $true;" ^
    "        Write-Output ('WARNING: All-user enumeration failed for ' + $label + ': ' + $_.Exception.Message);" ^
    "        Write-Output 'Attempting removal separately for every registered local profile SID.';" ^
    "    };" ^
    "};" ^
    "if (-not $allUsersAvailable) {" ^
    "    $profileKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList';" ^
    "    try {" ^
    "        $profileSids = @(" ^
    "            Get-ChildItem -LiteralPath $profileKey -ErrorAction Stop |" ^
    "                Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' } |" ^
    "                Select-Object -ExpandProperty PSChildName -Unique" ^
    "        );" ^
    "    } catch {" ^
    "        Write-Output ('ERROR: Could not enumerate profile SIDs: ' + $_.Exception.Message);" ^
    "        exit 1;" ^
    "    };" ^
    "    if ($profileSids.Count -eq 0) {" ^
    "        Write-Output 'NOTICE: No eligible profile SIDs were found for per-user package removal.';" ^
    "    };" ^
    "    foreach ($sid in $profileSids) {" ^
    "        try {" ^
    "            $userPackages = @(Get-AppxPackage -User $sid -Name $pattern -ErrorAction Stop);" ^
    "        } catch {" ^
    "            Write-Output ('ERROR: Package enumeration failed for SID ' + $sid + ': ' + $_.Exception.Message);" ^
    "            $failed++;" ^
    "            continue;" ^
    "        };" ^
    "        if ($userPackages.Count -eq 0) {" ^
    "            Write-Output ('SKIPPED: No installed ' + $label + ' package found for SID ' + $sid + '.');" ^
    "            continue;" ^
    "        };" ^
    "        foreach ($package in $userPackages) {" ^
    "            $attempted++;" ^
    "            try {" ^
    "                Write-Output ('Removing ' + $package.PackageFullName + ' for SID ' + $sid + '.');" ^
    "                Remove-AppxPackage -Package $package.PackageFullName -User $sid -ErrorAction Stop;" ^
    "                Write-Output ('SUCCESS: Removed ' + $package.PackageFullName + ' for SID ' + $sid + '.');" ^
    "                $removed++;" ^
    "            } catch {" ^
    "                Write-Output ('ERROR: Failed to remove ' + $package.PackageFullName + ' for SID ' + $sid + ': ' + $_.Exception.Message);" ^
    "                $failed++;" ^
    "            };" ^
    "        };" ^
    "    };" ^
    "};" ^
    "Write-Output ('Installed ' + $label + ' removal summary:');" ^
    "Write-Output ('  Packages attempted: ' + $attempted);" ^
    "Write-Output ('  Packages removed: ' + $removed);" ^
    "Write-Output ('  Failures: ' + $failed);" ^
    "if ($failed -gt 0) {" ^
    "    exit 1;" ^
    "} elseif ($usedPerUserFallback) {" ^
    "    exit 2;" ^
    "} else {" ^
    "    exit 0;" ^
    "}" >>"%LOGFILE%" 2>&1

set "AppxRC=%ERRORLEVEL%"
endlocal & exit /b %AppxRC%

:ProcessInstalledAppxPattern
setlocal DisableDelayedExpansion

set "AppxPattern=%~1"
set "AppxLabel=%~2"

call :RemoveAppxPattern "%AppxPattern%" "%AppxLabel%"
set "AppxResult=%ERRORLEVEL%"

if "%AppxResult%"=="0" (
    endlocal
    exit /b 0
)
if "%AppxResult%"=="2" (
    endlocal
    call :LOG NOTICE: All-user enumeration was unavailable for %~2.
    call :LOG NOTICE: Per-profile SID enumeration and removal completed successfully.
    exit /b 0
)
if "%AppxResult%"=="3" (
    endlocal
    call :LOG ERROR: RemoveAppxPattern was called incorrectly for %~2.
    exit /b 3
)
endlocal
call :LOG WARNING: Installed package processing failed for %~2.
exit /b 1

:BuildAppxInventory
setlocal DisableDelayedExpansion

set "AppxInventoryFile=%TEMP%\TBOK-AppxInventory-%COMPUTERNAME%.txt"
if exist "%AppxInventoryFile%" (
    del /q "%AppxInventoryFile%" >nul 2>&1
)

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    Get-AppxPackage -AllUsers -ErrorAction Stop |" ^
    "        ForEach-Object { $_.Name + '|' + $_.PackageFullName };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    exit 1;" ^
    "}" >"%AppxInventoryFile%" 2>nul

set "AppxInventoryRC=%ERRORLEVEL%"

if not "%AppxInventoryRC%"=="0" (
    if exist "%AppxInventoryFile%" (
        del /q "%AppxInventoryFile%" >nul 2>&1
    )
    endlocal & (
        set "TBOK_APPX_INVENTORY="
        set "TBOK_APPX_ALLUSERS_UNAVAILABLE=1"
        exit /b 1
    )
)
endlocal & (
    set "TBOK_APPX_INVENTORY=%TEMP%\TBOK-AppxInventory-%COMPUTERNAME%.txt"
    set "TBOK_APPX_ALLUSERS_UNAVAILABLE="
    exit /b 0
)

:RemoveProvisionedAppxPattern
setlocal DisableDelayedExpansion
set "TBOK_PROVISIONED_PATTERN=%~1"
set "TBOK_PROVISIONED_LABEL=%~2"

if not defined TBOK_PROVISIONED_PATTERN (
    endlocal
    call :LOG ERROR: RemoveProvisionedAppxPattern called without a package pattern.
    exit /b 2
)
if not defined TBOK_PROVISIONED_LABEL (
    set "TBOK_PROVISIONED_LABEL=%TBOK_PROVISIONED_PATTERN%"
)
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $pattern = $env:TBOK_PROVISIONED_PATTERN;" ^
    "    $label = $env:TBOK_PROVISIONED_LABEL;" ^
    "    $packages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object DisplayName -Like $pattern);" ^
    "    if ($packages.Count -eq 0) {" ^
    "        Write-Output ('SKIPPED: No provisioned ' + $label + ' packages were found.');" ^
    "        exit 0;" ^
    "    };" ^
    "    $failed = $false;" ^
    "    foreach ($package in $packages) {" ^
    "        try {" ^
    "            Write-Output ('Removing provisioned package: ' + $package.DisplayName);" ^
    "            $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null;" ^
    "            Write-Output ('SUCCESS: Removed provisioned package: ' + $package.DisplayName);" ^
    "        } catch {" ^
    "            Write-Output ('ERROR: Failed to remove ' + $package.DisplayName + ': ' + $_.Exception.Message);" ^
    "            $failed = $true;" ^
    "        };" ^
    "    };" ^
    "    if ($failed) { exit 1 } else { exit 0 }" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Provisioned-package query failed for ' + $label + ': ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

set "ProvisionedAppxRC=%ERRORLEVEL%"
endlocal & exit /b %ProvisionedAppxRC%

:ProcessProvisionedAppxPattern
setlocal DisableDelayedExpansion

call :RemoveProvisionedAppxPattern "%~1" "%~2"
set "ProvisionedResult=%ERRORLEVEL%"
if not "%ProvisionedResult%"=="0" (
    endlocal
    call :LOG WARNING: One or more provisioned %~2 packages could not be removed.
    exit /b 1
)
endlocal
exit /b 0

::::::::::::::::::::::::::::: SECTION START Begin Helpers for Control Sets mapping::::::::::::::::::::::::::::
:::::::This is used to match working -current, default, and lastknowngood sets to values persist
:InitializeControlSetTargets
set "TBOK_CS_CURRENT="
set "TBOK_CS_DEFAULT="
set "TBOK_CS_LASTKNOWNGOOD="
set "TBOK_CS_CURRENT_NUMBER="
set "TBOK_CS_DEFAULT_NUMBER="
set "TBOK_CS_LASTKNOWNGOOD_NUMBER="

for /f "tokens=3" %%A in ('REG query "HKLM\SYSTEM\Select" /v Current 2^>nul ^| findstr /I /C:"Current"') do (
    set /a "TBOK_CS_CURRENT_NUMBER=%%A"
)
for /f "tokens=3" %%A in ('REG query "HKLM\SYSTEM\Select" /v Default 2^>nul ^| findstr /I /C:"Default"') do (
    set /a "TBOK_CS_DEFAULT_NUMBER=%%A"
)
for /f "tokens=3" %%A in ('REG query "HKLM\SYSTEM\Select" /v LastKnownGood 2^>nul ^| findstr /I /C:"LastKnownGood"') do (
    set /a "TBOK_CS_LASTKNOWNGOOD_NUMBER=%%A"
)
if defined TBOK_CS_CURRENT_NUMBER (
    if !TBOK_CS_CURRENT_NUMBER! GTR 0 (
        set "TBOK_CS_PADDED=00!TBOK_CS_CURRENT_NUMBER!"
        set "TBOK_CS_CURRENT=ControlSet!TBOK_CS_PADDED:~-3!"
    )
)
if defined TBOK_CS_DEFAULT_NUMBER (
    if !TBOK_CS_DEFAULT_NUMBER! GTR 0 (
        set "TBOK_CS_PADDED=00!TBOK_CS_DEFAULT_NUMBER!"
        set "TBOK_CS_DEFAULT=ControlSet!TBOK_CS_PADDED:~-3!"
    )
)
if defined TBOK_CS_LASTKNOWNGOOD_NUMBER (
    if !TBOK_CS_LASTKNOWNGOOD_NUMBER! GTR 0 (
        set "TBOK_CS_PADDED=00!TBOK_CS_LASTKNOWNGOOD_NUMBER!"
        set "TBOK_CS_LASTKNOWNGOOD=ControlSet!TBOK_CS_PADDED:~-3!"
    )
)
set "TBOK_CS_PADDED="
if not defined TBOK_CS_CURRENT (
    call :LOG ERROR: The Current control-set mapping could not be determined.
    exit /b 1
)
if not defined TBOK_CS_DEFAULT (
    call :LOG ERROR: The Default control-set mapping could not be determined.
    exit /b 1
)
if not defined TBOK_CS_LASTKNOWNGOOD (
    call :LOG ERROR: The LastKnownGood control-set mapping could not be determined.
    exit /b 1
)
call :LOG Control-set role mappings:
call :LOG Current: !TBOK_CS_CURRENT!
call :LOG Default: !TBOK_CS_DEFAULT!
call :LOG LastKnownGood: !TBOK_CS_LASTKNOWNGOOD!
exit /b 0

:SetAllControlSetValues
setlocal EnableDelayedExpansion

set "TBOK_CS_RELATIVE_PATH=%~1"
set "TBOK_CS_VALUE_NAME=%~2"
set "TBOK_CS_VALUE_TYPE=%~3"
set "TBOK_CS_VALUE_DATA=%~4"
set "TBOK_CS_DESCRIPTION=%~5"
set "TBOK_CS_WRITE_FAILED=0"

if not defined TBOK_CS_RELATIVE_PATH (
    endlocal
    call :LOG ERROR: SetAllControlSetValues was called without a relative registry path.
    exit /b 2
)
if not defined TBOK_CS_VALUE_NAME (
    endlocal
    call :LOG ERROR: SetAllControlSetValues was called without a value name.
    exit /b 2
)
if not defined TBOK_CS_VALUE_TYPE (
    endlocal
    call :LOG ERROR: SetAllControlSetValues was called without a registry type.
    exit /b 2
)
if not defined TBOK_CS_CURRENT (
    endlocal
    call :LOG ERROR: Control-set mappings have not been initialized.
    exit /b 3
)
if not defined TBOK_CS_DESCRIPTION (
    set "TBOK_CS_DESCRIPTION=!TBOK_CS_VALUE_NAME!"
)
call :WriteControlSetValue ^
    "!TBOK_CS_CURRENT!" ^
    "!TBOK_CS_RELATIVE_PATH!" ^
    "!TBOK_CS_VALUE_NAME!" ^
    "!TBOK_CS_VALUE_TYPE!" ^
    "!TBOK_CS_VALUE_DATA!" ^
    "Current" ^
    "!TBOK_CS_DESCRIPTION!"

if errorlevel 1 set "TBOK_CS_WRITE_FAILED=1"
if /I not "!TBOK_CS_DEFAULT!"=="!TBOK_CS_CURRENT!" (
    call :WriteControlSetValue ^
        "!TBOK_CS_DEFAULT!" ^
        "!TBOK_CS_RELATIVE_PATH!" ^
        "!TBOK_CS_VALUE_NAME!" ^
        "!TBOK_CS_VALUE_TYPE!" ^
        "!TBOK_CS_VALUE_DATA!" ^
        "Default" ^
        "!TBOK_CS_DESCRIPTION!"

    if errorlevel 1 set "TBOK_CS_WRITE_FAILED=1"
)
if /I not "!TBOK_CS_LASTKNOWNGOOD!"=="!TBOK_CS_CURRENT!" if /I not "!TBOK_CS_LASTKNOWNGOOD!"=="!TBOK_CS_DEFAULT!" (
    call :WriteControlSetValue ^
        "!TBOK_CS_LASTKNOWNGOOD!" ^
        "!TBOK_CS_RELATIVE_PATH!" ^
        "!TBOK_CS_VALUE_NAME!" ^
        "!TBOK_CS_VALUE_TYPE!" ^
        "!TBOK_CS_VALUE_DATA!" ^
        "LastKnownGood" ^
        "!TBOK_CS_DESCRIPTION!"

    if errorlevel 1 set "TBOK_CS_WRITE_FAILED=1"
)
if "!TBOK_CS_WRITE_FAILED!"=="1" (
    endlocal
    exit /b 1
)
endlocal
exit /b 0

:WriteControlSetValue
setlocal DisableDelayedExpansion

set "ControlSetPath=HKLM\SYSTEM\%~1\%~2"
set "ControlSetDescription=%~7 for the %~6 role in HKLM\SYSTEM\%~1"

call :SetRegistryValue "%ControlSetPath%" "%~3" "%~4" "%~5" "%ControlSetDescription%"
set "WriteRC=%ERRORLEVEL%"

endlocal & exit /b %WriteRC%

::helper for writing registry values to avoid writing extra lines of code per command for errors and logging
:: Uses REG QUERY and REG ADD only for faster machine-level registry processing.
:: Equivalent hexadecimal and decimal DWORD representations may be reapplied.
:SetRegistryValue
setlocal EnableDelayedExpansion

set "RegPath=%~1"
set "RegName=%~2"
set "RegType=%~3"
set "RegData=%~4"
set "RegDescription=%~5"

if not defined RegPath (
    endlocal
    call :LOG ERROR: SetRegistryValue was called without a registry path.
    exit /b 2
)
if not defined RegName (
    endlocal
    call :LOG ERROR: SetRegistryValue was called without a value name.
    exit /b 2
)
if not defined RegType (
    endlocal
    call :LOG ERROR: SetRegistryValue was called without a registry type.
    exit /b 2
)
if not defined RegDescription (
    set "RegDescription=!RegName!"
)
set "CurrentType="
set "CurrentData="

for /f "skip=2 tokens=1,2,*" %%A in (
    'REG QUERY "!RegPath!" /v "!RegName!" 2^>nul'
) do (
    set "CurrentType=%%B"
    set "CurrentData=%%C"
)
if defined CurrentType (
    if /I "!CurrentType!"=="!RegType!" (
        if /I "!CurrentData!"=="!RegData!" (
            endlocal
            call :LOG MATCH: %~5 already equals %~4 [%~3]. No changes were made.
            exit /b 0
        )
    )

    set "OriginalType=!CurrentType!"
    set "OriginalData=!CurrentData!"
    set "ChangeMode=CHANGE"
) else (
    set "OriginalType=Not present"
    set "OriginalData=Not present"
    set "ChangeMode=CREATE"
)
REG ADD "!RegPath!" ^
    /v "!RegName!" ^
    /t "!RegType!" ^
    /d "!RegData!" ^
    /f >>"%LOGFILE%" 2>&1

set "RegistryWriteRC=!ERRORLEVEL!"

if not "!RegistryWriteRC!"=="0" (
    for %%R in ("!RegistryWriteRC!") do (
        endlocal
        call :LOG ERROR: Failed to configure %~5. Exit code: %%~R.
        exit /b 1
    )
)


if /I "!ChangeMode!"=="CREATE" (
    endlocal
    call :LOG CREATE: %~5 was not present; created as %~4 [%~3].
    exit /b 0
)
endlocal & call :LOG CHANGE: %~5 original value: %OriginalData% [%OriginalType%]; changed to: %~4 [%~3].
exit /b 0

:SetRegistryValueQuiet
:: Adds a registry key with named value while handling error types to reduce code, console noise, and log
setlocal DisableDelayedExpansion

if "%~1"=="" (
    endlocal
    call :LOG ERROR: SetRegistryValueQuiet was called without a registry path.
    exit /b 2
)
if "%~2"=="" (
    endlocal
    call :LOG ERROR: SetRegistryValueQuiet was called without a value name.
    exit /b 2
)
if "%~3"=="" (
    endlocal
    call :LOG ERROR: SetRegistryValueQuiet was called without a registry type.
    exit /b 2
)
REG ADD "%~1" /v "%~2" /t "%~3" /d "%~4" /f >nul 2>>"%LOGFILE%"
set "RegWriteRC=%ERRORLEVEL%"
if not "%RegWriteRC%"=="0" (
    endlocal
    call :LOG ERROR: Failed to configure %~5. Exit code: %RegWriteRC%.
    exit /b 1
)
endlocal
exit /b 0

:EnsureRegistryKey
::Adds a registry key without named value while handling error types to reduce code, console noise, and log
setlocal DisableDelayedExpansion

if "%~1"=="" (
    endlocal
    call :LOG ERROR: EnsureRegistryKey was called without a registry path.
    exit /b 2
)
REG ADD "%~1" /f >nul 2>>"%LOGFILE%"
set "RegistryKeyRC=%ERRORLEVEL%"

if not "%RegistryKeyRC%"=="0" (
    endlocal
    call :LOG ERROR: Failed to create or verify %~2. Exit code: %RegistryKeyRC%.
    exit /b 1
)
endlocal
exit /b 0

:DeleteRegistryKeyIfPresent
setlocal DisableDelayedExpansion
if "%~1"=="" (
    endlocal
    call :LOG ERROR: DeleteRegistryKeyIfPresent was called without a registry path.
    exit /b 2
)
REG query "%~1" >nul 2>&1
if errorlevel 1 (
    endlocal
    exit /b 0
)
REG delete "%~1" /f >nul 2>>"%LOGFILE%"
set "DeleteKeyRC=%ERRORLEVEL%"
if not "%DeleteKeyRC%"=="0" (
    endlocal
    call :LOG ERROR: Failed to delete %~2. Exit code: %DeleteKeyRC%.
    exit /b 1
)
endlocal
call :LOG Deleted %~2.
exit /b 0

:DeleteRegistryValueIfPresent
setlocal DisableDelayedExpansion
if "%~1"=="" (
    endlocal
    call :LOG ERROR: DeleteRegistryValueIfPresent was called without a registry path.
    exit /b 2
)
if "%~2"=="" (
    endlocal
    call :LOG ERROR: DeleteRegistryValueIfPresent was called without a value name.
    exit /b 2
)
REG query "%~1" /v "%~2" >nul 2>&1
if errorlevel 1 (
    endlocal
    exit /b 0
)
REG delete "%~1" /v "%~2" /f >nul 2>>"%LOGFILE%"
set "DeleteValueRC=%ERRORLEVEL%"
if not "%DeleteValueRC%"=="0" (
    endlocal
    call :LOG ERROR: Failed to delete %~3. Exit code: %DeleteValueRC%.
    exit /b 1
)
endlocal
call :LOG Deleted %~3.
exit /b 0

:SaveMountedHiveBackup
setlocal DisableDelayedExpansion

if not "%TBOK_RESTORE_POINT_FAILED%"=="1" (
    endlocal
    exit /b 0
)
if not defined TBOK_PROFILE_BACKUP_DIR (
    endlocal
    call :LOG WARNING: The profile backup directory is undefined for %~3.
    exit /b 1
)
if not exist "%TBOK_PROFILE_BACKUP_DIR%" (
    endlocal
    call :LOG WARNING: The profile backup directory is unavailable for %~3.
    exit /b 1
)
REG save "%~1" ^
    "%TBOK_PROFILE_BACKUP_DIR%\%~2" ^
    /y >>"%LOGFILE%" 2>&1

set "HiveBackupRC=%ERRORLEVEL%"
if not "%HiveBackupRC%"=="0" (
    endlocal
    call :LOG WARNING: Could not create a registry-native hive backup for %~3.
    exit /b 1
)
endlocal
call :LOG Created registry-native hive backup for %~3.
exit /b 0
::::::::::::::::::::::::::::: SECTION END Helpers for Control Sets mapping::::::::::::::::::::::::::::


:GetInstalledMemory
:: helper to get the currently installed physical memory values to be used
set "TBOK_MEMORY_KB="
set "TBOK_MEMORY_MB="
set "TBOK_MEMORY_GB="

for /f "usebackq tokens=1-3 delims=;" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$n=(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop | Measure-Object -Property Capacity -Sum).Sum;if($n){'{0:F0};{1:F0};{2:F0}' -f ($n/1KB),($n/1MB),($n/1GB)}" 2^>nul`) do (
    set "TBOK_MEMORY_KB=%%A"
    set "TBOK_MEMORY_MB=%%B"
    set "TBOK_MEMORY_GB=%%C"
)
if not defined TBOK_MEMORY_KB exit /b 1
if not defined TBOK_MEMORY_MB exit /b 1
if not defined TBOK_MEMORY_GB exit /b 1
exit /b 0

:ResolveMemoryPolicy
:: Low-memory systems keep SysMain Automatic so MMAgent workers remain available.
:: This policy applies to SSD, HDD, RAID, and unknown storage.
:: Higher-memory systems use the storage-based SysMain policy and do not modify MMAgent.
set "TBOK_SYSMAIN_MODE=unchanged"
set "TBOK_LOW_MEMORY=0"
set "TBOK_MANAGE_MMAGENT=0"

if not defined TBOK_MEMORY_MB (
    call :LOG ERROR: Installed RAM is unavailable.
    call :LOG The SysMain and MMAgent policy could not be resolved.
    exit /b 1
)
if !TBOK_MEMORY_MB! LEQ 12288 (
    set "TBOK_LOW_MEMORY=1"
    set "TBOK_MANAGE_MMAGENT=1"
    set "TBOK_SYSMAIN_MODE=auto"
) else if /I "!TBOK_DRIVETYPE!"=="SSD" (
    set "TBOK_SYSMAIN_MODE=disabled"
) else if /I "!TBOK_DRIVETYPE!"=="HDD" (
    set "TBOK_SYSMAIN_MODE=demand"
)
call :LOG Resolved memory policy:
call :LOG Installed RAM: !TBOK_MEMORY_MB! MB
call :LOG Storage profile: !TBOK_DRIVETYPE!
call :LOG Low-memory profile: !TBOK_LOW_MEMORY!
call :LOG Manage MMAgent features: !TBOK_MANAGE_MMAGENT!
call :LOG SysMain target mode: !TBOK_SYSMAIN_MODE!
exit /b 0

:: Configure MMAgent features only for the low-memory profile.
:ConfigureMemoryFeatures
if not "!TBOK_MANAGE_MMAGENT!"=="1" (
    call :LOG MMAgent settings were left unchanged because this is not a low-memory profile.
    exit /b 0
)

call :LOG Configuring SysMain and MMAgent for the low-memory profile...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$criticalFailure = $false;" ^
    "$optionalFailure = $false;" ^
    "try {" ^
    "    Set-Service -Name SysMain -StartupType Automatic -ErrorAction Stop;" ^
    "    $sysMain = Get-Service -Name SysMain -ErrorAction Stop;" ^
    "    if ($sysMain.Status -ne 'Running') {" ^
    "        Start-Service -Name SysMain -ErrorAction Stop;" ^
    "        $sysMain.WaitForStatus('Running', (New-TimeSpan -Seconds 15));" ^
    "    };" ^
    "    $sysMain = Get-Service -Name SysMain -ErrorAction Stop;" ^
    "    Write-Output ('SysMain startup target=Automatic; Status=' + $sysMain.Status);" ^
    "    if ($sysMain.Status -ne 'Running') { throw 'SysMain did not reach the Running state.' };" ^
    "} catch {" ^
    "    Write-Output ('ERROR: SysMain could not be prepared for MMAgent: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "};" ^
    "try {" ^
    "    Enable-MMAgent -MemoryCompression -ErrorAction Stop;" ^
    "    Write-Output 'APPLIED: Memory compression enable was requested.';" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Memory compression could not be enabled: ' + $_.Exception.Message);" ^
    "    $criticalFailure = $true;" ^
    "};" ^
    "try {" ^
    "    Enable-MMAgent -PageCombining -ErrorAction Stop;" ^
    "    Write-Output 'APPLIED: Page combining enable was requested.';" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Page combining could not be enabled: ' + $_.Exception.Message);" ^
    "    $criticalFailure = $true;" ^
    "};" ^
    "try {" ^
    "    Disable-MMAgent -ApplicationPreLaunch -ErrorAction Stop;" ^
    "    Write-Output 'APPLIED: Application prelaunch disable was requested.';" ^
    "} catch {" ^
    "    Write-Output ('NOTICE: Application prelaunch was left unchanged: ' + $_.Exception.Message);" ^
    "    $optionalFailure = $true;" ^
    "};" ^
    "try {" ^
    "    $final = Get-MMAgent -ErrorAction Stop;" ^
    "    $sysMain = Get-Service -Name SysMain -ErrorAction Stop;" ^
    "    Write-Output ('Final SysMainStatus=' + $sysMain.Status);" ^
    "    Write-Output ('Final MemoryCompression=' + $final.MemoryCompression);" ^
    "    Write-Output ('Final ApplicationLaunchPrefetching=' + $final.ApplicationLaunchPrefetching);" ^
    "    Write-Output ('Final ApplicationPreLaunch=' + $final.ApplicationPreLaunch);" ^
    "    Write-Output ('Final OperationAPI=' + $final.OperationAPI);" ^
    "    Write-Output ('Final PageCombining=' + $final.PageCombining);" ^
    "    if ($sysMain.Status -ne 'Running') {" ^
    "        Write-Output 'ERROR: SysMain is not running after MMAgent configuration.';" ^
    "        $criticalFailure = $true;" ^
    "    };" ^
    "    if (-not $final.MemoryCompression) {" ^
    "        Write-Output 'ERROR: Memory compression is not enabled in the final MMAgent state.';" ^
    "        $criticalFailure = $true;" ^
    "    };" ^
    "    if (-not $final.PageCombining) {" ^
    "        Write-Output 'ERROR: Page combining is not enabled in the final MMAgent state.';" ^
    "        $criticalFailure = $true;" ^
    "    };" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Final SysMain or MMAgent state could not be verified: ' + $_.Exception.Message);" ^
    "    $criticalFailure = $true;" ^
    "};" ^
    "if ($optionalFailure) {" ^
    "    Write-Output 'NOTICE: One optional MMAgent setting was unsupported and was left unchanged.';" ^
    "};" ^
    "Write-Output 'NOTICE: A restart is required to validate the persistent SysMain and MMAgent state.';" ^
    "if ($criticalFailure) { exit 1 } else { exit 0 }" ^
    >>"%LOGFILE%" 2>&1

set "MemoryFeaturesRC=!ERRORLEVEL!"

if not "!MemoryFeaturesRC!"=="0" (
    call :LOG WARNING: Low-memory SysMain or MMAgent configuration failed.
    exit /b 1
)

call :LOG Low-memory SysMain and MMAgent configuration completed.
exit /b 0

:: Capture a Windows memory snapshot and write it to the console and logfile.
:CaptureMemorySnapshot
setlocal DisableDelayedExpansion

set "TBOK_MEMORY_LABEL=%~1"
if not defined TBOK_MEMORY_LABEL (
    set "TBOK_MEMORY_LABEL=UNLABELED"
)
set "TBOK_MEMORY_FILE=%TEMP%\TBOK-Memory-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "try {" ^
    "    $label = $env:TBOK_MEMORY_LABEL;" ^
    "    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop;" ^
    "    $memory = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop;" ^
    "    $physicalModules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop);" ^
    "    $totalInstalledBytes = [double]0;" ^
    "    foreach ($physicalModule in $physicalModules) {" ^
    "        $totalInstalledBytes += [double]$physicalModule.Capacity;" ^
    "    };" ^
    "    if ($totalInstalledBytes -le 0) {" ^
    "        throw 'Installed physical memory could not be determined.';" ^
    "    };" ^
    "    $totalVisibleBytes = [double]$os.TotalVisibleMemorySize * 1KB;" ^
    "    $availableBytes = [double]$memory.AvailableBytes;" ^
    "    $usedVisibleBytes = $totalVisibleBytes - $availableBytes;" ^
    "    $hardwareReservedBytes = $totalInstalledBytes - $totalVisibleBytes;" ^
    "    if ($hardwareReservedBytes -lt 0) {" ^
    "        $hardwareReservedBytes = 0;" ^
    "    };" ^
    "    $committedBytes = [double]$memory.CommittedBytes;" ^
    "    $commitLimitBytes = [double]$memory.CommitLimit;" ^
    "    $physicalUsedPercent = if ($totalVisibleBytes -gt 0) {" ^
    "        100 * $usedVisibleBytes / $totalVisibleBytes;" ^
    "    } else {" ^
    "        0;" ^
    "    };" ^
    "    $commitUsedPercent = if ($commitLimitBytes -gt 0) {" ^
    "        100 * $committedBytes / $commitLimitBytes;" ^
    "    } else {" ^
    "        0;" ^
    "    };" ^
    "    $currentProcessId = $PID;" ^
    "    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentProcessId });" ^
    "    $svchost = @($processes | Where-Object { $_.ProcessName -eq 'svchost' });" ^
    "    $svchostWorkingSet = ($svchost | Measure-Object -Property WorkingSet64 -Sum).Sum;" ^
    "    $svchostPrivate = ($svchost | Measure-Object -Property PrivateMemorySize64 -Sum).Sum;" ^
    "    if ($null -eq $svchostWorkingSet) {" ^
    "        $svchostWorkingSet = 0;" ^
    "    };" ^
    "    if ($null -eq $svchostPrivate) {" ^
    "        $svchostPrivate = 0;" ^
    "    };" ^
    "    $compressionProcesses = @(Get-Process -Name 'Memory Compression' -ErrorAction SilentlyContinue);" ^
    "    $compressionWorkingSet = ($compressionProcesses | Measure-Object -Property WorkingSet64 -Sum).Sum;" ^
    "    if ($null -eq $compressionWorkingSet) {" ^
    "        $compressionWorkingSet = 0;" ^
    "    };" ^
    "    Write-Output '================================================================';" ^
    "    Write-Output ('MEMORY SNAPSHOT: ' + $label);" ^
    "    Write-Output ('Captured: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'));" ^
    "    Write-Output '================================================================';" ^
    "    Write-Output ('Installed physical memory : {0:N2} GB' -f ($totalInstalledBytes / 1GB));" ^
    "    Write-Output ('Usable physical memory    : {0:N2} GB' -f ($totalVisibleBytes / 1GB));" ^
    "    Write-Output ('Physical memory in use    : {0:N2} GB ({1:N1} percent)' -f ($usedVisibleBytes / 1GB), $physicalUsedPercent);" ^
    "    Write-Output ('Available physical memory : {0:N2} GB' -f ($availableBytes / 1GB));" ^
    "    Write-Output ('Hardware reserved memory  : {0:N0} MB' -f ($hardwareReservedBytes / 1MB));" ^
    "    Write-Output ('Committed memory          : {0:N2} GB' -f ($committedBytes / 1GB));" ^
    "    Write-Output ('Commit limit              : {0:N2} GB' -f ($commitLimitBytes / 1GB));" ^
    "    Write-Output ('Commit utilization        : {0:N1} percent' -f $commitUsedPercent);" ^
    "    Write-Output ('System cache              : {0:N0} MB' -f ([double]$memory.CacheBytes / 1MB));" ^
    "    Write-Output ('Paged pool                : {0:N0} MB' -f ([double]$memory.PoolPagedBytes / 1MB));" ^
    "    Write-Output ('Nonpaged pool             : {0:N0} MB' -f ([double]$memory.PoolNonpagedBytes / 1MB));" ^
    "    Write-Output ('Memory compression        : {0:N0} MB' -f ([double]$compressionWorkingSet / 1MB));" ^
    "    Write-Output ('Running processes         : ' + $processes.Count);" ^
    "    Write-Output ('svchost process count     : ' + $svchost.Count);" ^
    "    Write-Output ('svchost working set       : {0:N0} MB' -f ([double]$svchostWorkingSet / 1MB));" ^
    "    Write-Output ('svchost private memory    : {0:N0} MB' -f ([double]$svchostPrivate / 1MB));" ^
    "    Write-Output '';" ^
    "    Write-Output 'Top processes by working set:';" ^
    "    $topProcesses = @($processes | Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 10);" ^
    "    foreach ($process in $topProcesses) {" ^
    "        Write-Output ('  {0,-28} PID={1,-7} WorkingSet={2,7:N0} MB Private={3,7:N0} MB' -f $process.ProcessName, $process.Id, ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB));" ^
    "    };" ^
    "    Write-Output '================================================================';" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Memory snapshot failed: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >"%TBOK_MEMORY_FILE%" 2>&1

set "TBOK_MEMORY_RC=%ERRORLEVEL%"

if exist "%TBOK_MEMORY_FILE%" (
    for /f "usebackq delims=" %%M in ("%TBOK_MEMORY_FILE%") do (
        call :LOG %%M
    )
    del /q "%TBOK_MEMORY_FILE%" >nul 2>&1
)
if not "%TBOK_MEMORY_RC%"=="0" (
    endlocal
    call :LOG WARNING: Memory snapshot "%~1" failed with exit code %TBOK_MEMORY_RC%.
    exit /b 1
)
endlocal
exit /b 0

:GetChassisType
:: Helper for Chassis type detection to avoid enabling desktop tweaks on a device with a battery - Returns Laptop, Desktop, or Unknown in CHASSISTYPE for later logic use
set "CHASSISTYPE=Unknown"
for /f "delims=" %%G in ('powershell.exe -NoProfile -Command "$ct=@((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes); if($null -ne ($ct -as [array])){if($ct -match '^(8|9|10|11|12|14|18|21|30|31|32)$'){'Laptop'}elseif($ct -match '^(3|4|5|6|7|13|15|16|24|35|36)$'){'Desktop'}else{'Unknown'}}else{'Unknown'}" 2^>nul') do set "CHASSISTYPE=%%G"
exit /b

:GetSystemProfile
:: Helper to build variables required hardware profile for specific scenario optimizations
call :LOG Building hardware profile...
call :GetInstalledMemory
set "SystemProfileMemoryRC=!ERRORLEVEL!"
if not "!SystemProfileMemoryRC!"=="0" (
    call :LOG WARNING: Installed memory could not be determined.
)
call :GetChassisType
call :LOG Chassis profile: !CHASSISTYPE!
::Detect whether the Windows system drive is an HDD or SSD and physical media type 
set "TBOK_DRIVETYPE=UNKNOWN"
set "DriveDetectRC="
set "DriveDetectFile=%TEMP%\TBOK-DriveDetect-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

call :LOG Detecting Windows system drive media type...
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "try {" ^
    "    $driveLetter = $env:SystemDrive.TrimEnd(':');" ^
    "    $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop;" ^
    "    $disk = $partition | Get-Disk -ErrorAction Stop;" ^
    "    $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue);" ^
    "    $matchingPhysical = @($physicalDisks | Where-Object { [string]$_.DeviceId -eq [string]$disk.Number });" ^
    "    if ($matchingPhysical.Count -eq 0 -and $physicalDisks.Count -eq 1) {" ^
    "        $matchingPhysical = $physicalDisks;" ^
    "    };" ^
    "    $isRotational = $false;" ^
    "    $isSolidState = $false;" ^
    "    if ([string]$disk.MediaType -eq 'HDD') {" ^
    "        $isRotational = $true;" ^
    "    } elseif ([string]$disk.MediaType -match 'SSD|SCM') {" ^
    "        $isSolidState = $true;" ^
    "    };" ^
    "    foreach ($physicalDisk in $matchingPhysical) {" ^
    "        if ([string]$physicalDisk.MediaType -eq 'HDD') {" ^
    "            $isRotational = $true;" ^
    "        } elseif ([string]$physicalDisk.MediaType -match 'SSD|SCM') {" ^
    "            $isSolidState = $true;" ^
    "        };" ^
    "        if ($null -ne $physicalDisk.SpindleSpeed) {" ^
    "            if ([uint64]$physicalDisk.SpindleSpeed -gt 0) {" ^
    "                $isRotational = $true;" ^
    "            } elseif ([uint64]$physicalDisk.SpindleSpeed -eq 0) {" ^
    "                $isSolidState = $true;" ^
    "            };" ^
    "        };" ^
    "    };" ^
    "    Write-Output ('DETAIL: DiskNumber=' + $disk.Number + '; BusType=' + $disk.BusType + '; MediaType=' + $disk.MediaType + '; FriendlyName=' + $disk.FriendlyName);" ^
    "    foreach ($physicalDisk in $matchingPhysical) {" ^
    "        Write-Output ('DETAIL: PhysicalDisk=' + $physicalDisk.FriendlyName + '; MediaType=' + $physicalDisk.MediaType + '; SpindleSpeed=' + $physicalDisk.SpindleSpeed);" ^
    "    };" ^
    "    if ($isRotational) {" ^
    "        Write-Output 'RESULT=HDD';" ^
    "    } elseif ($isSolidState) {" ^
    "        Write-Output 'RESULT=SSD';" ^
    "    } elseif ([string]$disk.BusType -eq 'NVMe') {" ^
    "        Write-Output 'RESULT=SSD';" ^
    "    } elseif ([string]$disk.BusType -eq 'RAID') {" ^
    "        Write-Output 'RESULT=UNKNOWN';" ^
    "    } else {" ^
    "        Write-Output 'RESULT=UNKNOWN';" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR=' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >"%DriveDetectFile%" 2>&1
set "DriveDetectRC=!ERRORLEVEL!"
if exist "%DriveDetectFile%" (
    type "%DriveDetectFile%" >>"%LOGFILE%"
)
if not "!DriveDetectRC!"=="0" (
    call :LOG WARNING: Drive detection PowerShell returned exit code !DriveDetectRC!.
    
	if defined DriveDetectFile (
        if exist "!DriveDetectFile!" (
            for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"ERROR=" "!DriveDetectFile!" 2^>nul') do (
                call :LOG Drive detection error: %%B
            )
        )
    )
	
    goto :GetSystemProfileCleanup
)
for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"RESULT=" "%DriveDetectFile%" 2^>nul') do (
    set "TBOK_DRIVETYPE=%%B"
)
if /i not "!TBOK_DRIVETYPE!"=="HDD" if /i not "!TBOK_DRIVETYPE!"=="SSD" (
    set "TBOK_DRIVETYPE=UNKNOWN"
)
:GetSystemProfileCleanup
if defined DriveDetectFile (
    if exist "%DriveDetectFile%" (
        del /q "%DriveDetectFile%" >nul 2>&1
    )
)
call :LOG Storage profile: !TBOK_DRIVETYPE!
exit /b 0

:InitializeTemporaryPlans
set "TBOK_SERVICE_PLAN=%TEMP%\TBOK-ServicePlan-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"
set "TBOK_TASK_PLAN=%TEMP%\TBOK-TaskPlan-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

if exist "!TBOK_SERVICE_PLAN!" (
    del /q "!TBOK_SERVICE_PLAN!" >nul 2>&1
)
if exist "!TBOK_TASK_PLAN!" (
    del /q "!TBOK_TASK_PLAN!" >nul 2>&1
)
exit /b 0

:CleanupTemporaryPlans
if defined TBOK_SERVICE_PLAN (
    if exist "%TBOK_SERVICE_PLAN%" (
        del /q "%TBOK_SERVICE_PLAN%" >nul 2>&1
    )
)
if defined TBOK_TASK_PLAN (
    if exist "%TBOK_TASK_PLAN%" (
        del /q "%TBOK_TASK_PLAN%" >nul 2>&1
    )
)
if defined TBOK_APPX_INVENTORY (
    if exist "%TBOK_APPX_INVENTORY%" (
        del /q "%TBOK_APPX_INVENTORY%" >nul 2>&1
    )
)
exit /b 0

:Delay
::helper for adding a delay compatible with powershell enter-pssession and other non-interactive
setlocal DisableDelayedExpansion
set "DelaySeconds=%~1"
if not defined DelaySeconds (
    endlocal
    exit /b 2
)
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds %DelaySeconds%" >nul 2>&1
set "DelayRC=%ERRORLEVEL%"
endlocal & exit /b %DelayRC%

:NonInteractiveSequence
::allows multiple run types to be done in sequence with a single command line
set "TBOK_NONINTERACTIVE=1"
set "TBOK_SEQUENCE_ACTIVE=1"
set "TBOK_SEQUENCE_FAILED=0"

call :LOG ================================================================
call :LOG Starting requested noninteractive operation sequence
call :LOG ================================================================

if defined TBOK_RUN_OPTIMIZE (
    call :LOG Sequence operation: System and user optimizations
    call :SYSTEMTWEAKS
    set "TBOK_OPERATION_RC=!ERRORLEVEL!"

    if not "!TBOK_OPERATION_RC!"=="0" (
        call :LOG ERROR: System and user optimizations returned exit code !TBOK_OPERATION_RC!.
        set "TBOK_SEQUENCE_FAILED=1"
    ) else (
        call :LOG Sequence operation completed: System and user optimizations
    )
)

if defined TBOK_RUN_CLEANUP (
    call :LOG Sequence operation: BeardSweeper cleanup
    call :BeardSweeper
    set "TBOK_OPERATION_RC=!ERRORLEVEL!"

    if not "!TBOK_OPERATION_RC!"=="0" (
        call :LOG ERROR: BeardSweeper cleanup returned exit code !TBOK_OPERATION_RC!.
        set "TBOK_SEQUENCE_FAILED=1"
    ) else (
        call :LOG Sequence operation completed: BeardSweeper cleanup
    )
)

if defined TBOK_RUN_GAMING (
    call :LOG Sequence operation: Gaming optimizations
    call :GamingTweaks
    set "TBOK_OPERATION_RC=!ERRORLEVEL!"

    if not "!TBOK_OPERATION_RC!"=="0" (
        call :LOG ERROR: Gaming optimizations returned exit code !TBOK_OPERATION_RC!.
        set "TBOK_SEQUENCE_FAILED=1"
    ) else (
        call :LOG Sequence operation completed: Gaming optimizations
    )
)

if defined TBOK_RUN_WINGET (
    call :LOG Sequence operation: WinGet application updates
    call :WinGet
    set "TBOK_OPERATION_RC=!ERRORLEVEL!"

    if not "!TBOK_OPERATION_RC!"=="0" (
        call :LOG ERROR: WinGet application updates returned exit code !TBOK_OPERATION_RC!.
        set "TBOK_SEQUENCE_FAILED=1"
    ) else (
        call :LOG Sequence operation completed: WinGet application updates
    )
)

call :LOG ================================================================
if "!TBOK_SEQUENCE_FAILED!"=="1" (
    call :LOG WARNING: The requested operation sequence completed with one or more failures.
) else (
    call :LOG Requested operation sequence completed successfully.
)
call :LOG ================================================================

set "TBOK_OPERATION_RC="
set "TBOK_SEQUENCE_ACTIVE="
set "TBOK_RUN_OPTIMIZE="
set "TBOK_RUN_CLEANUP="
set "TBOK_RUN_GAMING="
set "TBOK_RUN_WINGET="
set "TBOK_RUN_EXIT="
set "TBOK_ARGUMENT_ERROR="
goto :Finished

:END-SCRIPT-HELPERS

:MENU
TITLE TBOK Windows Performance Optimizer Version %version% %verdate%
::MAKE SOUND rundll32.exe cmdext.dll,MessageBeepStub
ECHO Script now supports arguments for non-interactive sessions
ECHO "run with /optimize /cleanup /gaming /winget /restart /newlog  for a menuless run"
ECHO ============================================================
ECHO                  THE BEARD OF KNOWLEDGE
ECHO.
ECHO        ::::::::::: :::::::::   ::::::::  :::    ::: 
ECHO           :+:     :+:    :+: :+:    :+: :+:   :+:   
ECHO          +:+     +:+    +:+ +:+    +:+ +:+  +:+     
ECHO         +#+     +#++:++#+  +#+    +:+ +#++:++       
ECHO        +#+     +#+    +#+ +#+    +#+ +#+  +#+       
ECHO       #+#     #+#    #+# #+#    #+# #+#   #+#       
ECHO      ###     #########   ########  ###    ### 
ECHO.
ECHO ============================================================
ECHO  Welcome to TBOK Windows Performance Optimizer and Debloat
ECHO             Version %version% %verdate%
ECHO.
ECHO Please choose
ECHO 1. Apply system and user level improvements -RECOMMENDED START*Default Autorun*
ECHO 2. Run BeardSweeper Ultimate Disk and Cache Cleanup routine
ECHO 3. Apply only gaming tweaks - for desktops only
ECHO 4. Update all apps using WinGet
ECHO 5. EXIT
ECHO.
ECHO IF THIS HELPED YOU OUT -CONSIDER BUYING ME A COFFEE- THATS WHAT POWERED THIS
ECHO "https://buymeacoffee.com/thebeardofl"
ECHO.
ECHO ============================================================
choice.exe /c 12345 /n /m "Enter 1-5: (Default: 1 in 15 seconds): " /t 15 /d 1 2>>"%LOGFILE%"
set "MenuChoiceRC=%ERRORLEVEL%"

if "%MenuChoiceRC%"=="255" (
    call :LOG NOTICE: Interactive console input is unavailable.
    call :LOG NOTICE: Defaulting to menu option 1 - System and user improvements.
    call :SYSTEMTWEAKS
    goto :Finished
)
if "%MenuChoiceRC%"=="5" goto :EXIT

if "%MenuChoiceRC%"=="4" (
    call :WinGet
    goto :Finished
)
if "%MenuChoiceRC%"=="3" (
    call :GamingTweaks
    goto :Finished
)
if "%MenuChoiceRC%"=="2" (
    call :BeardSweeper
    goto :Finished
)
if "%MenuChoiceRC%"=="1" (
    call :SYSTEMTWEAKS
    goto :Finished
)

call :LOG ERROR: Unexpected menu return code: %MenuChoiceRC%.
goto :EXIT

:SYSTEMTWEAKS
call :CleanupTemporaryPlans
call :InitializeTemporaryPlans
call :GetSystemProfile
ECHO Creating Log file and adding system information
call :LOG Detected:

ver >>"%LOGFILE%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" >>"%LOGFILE%" 2>&1

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object Vendor, Name, IdentifyingNumber" >>"%LOGFILE%" 2>&1

::get installed memory total variable
set "InstalledMemoryRC=0"
if not defined TBOK_MEMORY_MB (
set "InstalledMemoryRC=1"
)
if not "!InstalledMemoryRC!"=="0" (
    call :LOG WARNING: Installed physical memory could not be determined.
) else (
    call :LOG Installed physical memory: !TBOK_MEMORY_MB! MB
)

:BaselineMemUseSnapshot
call :LOG Capturing baseline memory usage before modifications...
call :CaptureMemorySnapshot "BEFORE SYSTEM AND USER OPTIMIZATIONS"
set "BaselineMemoryRC=!ERRORLEVEL!"
if not "!BaselineMemoryRC!"=="0" (
    call :LOG WARNING: The baseline memory snapshot could not be completed.
)
call :AuditStartupItems
set "StartupAuditRC=!ERRORLEVEL!"
if not "!StartupAuditRC!"=="0" (
    call :LOG WARNING: The startup-item audit could not be completed.
)
call :RequireRollbackProtection "System and user optimization changes"
if errorlevel 1 (
    call :LOG ERROR: System and user optimizations were canceled because complete rollback protection could not be created.
    exit /b 1
)

:MemoryUseOptimization
call :ResolveMemoryPolicy
set "MemoryPolicyRC=!ERRORLEVEL!"

if not "!MemoryPolicyRC!"=="0" (
    call :LOG WARNING: The SysMain and MMAgent policy could not be resolved.
) else (
    call :ConfigureMemoryFeatures
    set "MemoryFeaturesRC=!ERRORLEVEL!"

    if not "!MemoryFeaturesRC!"=="0" (
        call :LOG WARNING: One or more MMAgent memory settings could not be verified or configured.
    )
)

call :LOG Resolving Current, Default, and LastKnownGood control-set mappings...
call :InitializeControlSetTargets
set "ControlSetMappingRC=!ERRORLEVEL!"
if not "!ControlSetMappingRC!"=="0" (
    call :LOG CRITICAL: Control-set role mappings could not be determined.
    call :LOG System and user optimizations were stopped before control-set-specific changes were applied.
    exit /b 1
)

ECHO.
ECHO.
call :LOG **********************************************************
call :LOG              Starting System Optimizations               
call :LOG **********************************************************
:hibernation
call :LOG Setting Hibernation Mode based on PC chassis type
call :LOG Should be disabled for desktops-especially with SSD or NVME
::	Reasons to leave Hibernation/Fast Startup/Hybrid Shutdown disabled on desktops...
::	1. Most modern PC's come with an SSD or m2 NVME drive and fast startup is not required
::     it was made to improve performance for systems with slower spinning disks
::	2. Hybrid shutdown/hibernation/fast startup often causes Windows Updates to NOT install properly.
::	3. "system up time" timer in task manager keeps running with this enabled.
::	4. Software with poor memory management design can cause excess ram usage
::	Only Reason to enable it is on a laptop:
::	Only good thing from Hibernate/Fast Startup is if your Laptop/Tablet battery reaches critical while in sleep/standby mode...
::	your open files are saved because the laptop will wake and save data in ram to hibernation file, then shutdown.

:detectchassis
call :LOG Detected chassis category: !CHASSISTYPE!
if /i "!CHASSISTYPE!"=="Laptop" goto laptop
if /i "!CHASSISTYPE!"=="Desktop" goto desktop
goto unknownchassis

:laptop
call :LOG Laptop detected - enabling hibernation and fast startup mode
powercfg.exe /hibernate on >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG ERROR: Failed to enable hibernation.
) else (
    call :LOG Hibernation enabled successfully.
)
goto f8startup

:desktop
call :LOG Desktop detected - disabling hibernation and fast startup mode
powercfg.exe /hibernate off >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG ERROR: Failed to disable hibernation.
) else (
    call :LOG Hibernation disabled successfully.
)
goto f8startup

:unknownchassis
call :LOG Unable to determine chassis type. Hibernation was not changed.
goto f8startup
	
:F8startup
call :LOG Restoring the much beloved F8 Startup menu availability - WHY DID THEY REMOVE THAT
::This is optional to enable but a good default to Restore
::Microsoft default wants you to power cycle your PC 2 times before giving you boot options - waste of time
::If you have bitlocker enabled - using F8 will prompt you for the recovery key when you use the legacy boot menu - be aware
bcdedit.exe /set {default} bootmenupolicy legacy >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG ERROR: Failed to enable the legacy F8 boot menu.
) else (
    call :LOG Legacy F8 boot menu enabled successfully.
)
ECHO.

:virtualmemory
call :LOG Reviewing Windows page-file placement and sizing
call :LOG Existing page-file locations will be retained
call :LOG Systems with at least 32 GB of installed RAM will be left unchanged

set "PageFileRamMB=!TBOK_MEMORY_MB!"
set "PageFileInitialMB="
set "PageFileMaximumMB="
set "PageFileName="
set "PageFileCurrentInitialMB=0"
set "PageFileCurrentMaximumMB=0"
set "PageFileFreeMB="
set "PageFileAutomatic="
set "PageFileSettingCount=0"
set "PageFileActiveCount=0"

if not defined PageFileRamMB (
    call :LOG ERROR: Installed memory could not be determined.
    call :LOG Page-file settings were left unchanged.
    goto :SERVICES
)
call :LOG Installed RAM: !PageFileRamMB! MB

:: Leave systems with at least 32 GB unchanged.
if !PageFileRamMB! GEQ 32768 (
    call :LOG Installed RAM is 32 GB or greater.
    call :LOG Page-file management mode, locations, and sizes were left unchanged.
    goto :SERVICES
)

:: Select target sizes.
if !PageFileRamMB! LSS 8192 (
    set "PageFileInitialMB=4096"
    set "PageFileMaximumMB=16384"
) else if !PageFileRamMB! LSS 16384 (
    set "PageFileInitialMB=8192"
    set "PageFileMaximumMB=24576"
) else (
    set "PageFileInitialMB=8192"
    set "PageFileMaximumMB=32768"
)

call :LOG Target page-file sizes: Initial=!PageFileInitialMB! MB; Maximum=!PageFileMaximumMB! MB

:: Determine whether automatic page-file management is enabled.
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "(Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).AutomaticManagedPagefile" 2^>nul`) do set "PageFileAutomatic=%%A"

if not defined PageFileAutomatic (
    call :LOG ERROR: Automatic page-file management status could not be determined.
    call :LOG Page-file settings were left unchanged.
    goto :SERVICES
)

call :LOG Automatic page-file management: !PageFileAutomatic!

:: Count explicitly configured page-file settings.
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "@(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue).Count" 2^>nul`) do set "PageFileSettingCount=%%A"

if not defined PageFileSettingCount set "PageFileSettingCount=0"

:: Read the preferred explicit setting, favoring the Windows system drive.
if !PageFileSettingCount! GTR 0 (
    for /f "usebackq tokens=1-3 delims=;" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$p=Get-CimInstance Win32_PageFileSetting -ErrorAction Stop;$s=$p | Where-Object Name -Like ($env:SystemDrive+'\*') | Select-Object -First 1;if(-not $s){$s=$p | Sort-Object Name | Select-Object -First 1};'{0};{1};{2}' -f $s.Name,$s.InitialSize,$s.MaximumSize" 2^>nul`) do (
        set "PageFileName=%%A"
        set "PageFileCurrentInitialMB=%%B"
        set "PageFileCurrentMaximumMB=%%C"
    )
) else (
    :: No explicit setting exists. Examine active page files.
    for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "@(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue).Count" 2^>nul`) do set "PageFileActiveCount=%%A"

    if not defined PageFileActiveCount set "PageFileActiveCount=0"

    if !PageFileActiveCount! GTR 1 (
        call :LOG Multiple automatically managed page files were found.
        call :LOG Their locations and settings were left unchanged.
        goto :SERVICES
    )

    if !PageFileActiveCount! EQU 1 (
        for /f "usebackq tokens=1-2 delims=;" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$p=Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | Select-Object -First 1;'{0};{1}' -f $p.Name,$p.AllocatedBaseSize" 2^>nul`) do (
            set "PageFileName=%%A"
            set "PageFileCurrentMaximumMB=%%B"
        )
    ) else (
        set "PageFileName=%SystemDrive%\pagefile.sys"
        set "PageFileCurrentMaximumMB=0"
    )
)

if not defined PageFileName (
    call :LOG ERROR: A page-file location could not be determined.
    call :LOG Page-file settings were left unchanged.
    goto :SERVICES
)

call :LOG Selected page-file location: !PageFileName!

if !PageFileSettingCount! GTR 0 (
    call :LOG Current sizes: Initial=!PageFileCurrentInitialMB! MB; Maximum=!PageFileCurrentMaximumMB! MB
)

:: Determine available space on the selected page-file drive.
set "TBOK_PAGEFILE_NAME=!PageFileName!"

for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$r=[IO.Path]::GetPathRoot($env:TBOK_PAGEFILE_NAME);if($r){$d=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID='''+$r.TrimEnd('\')+'''') -ErrorAction Stop;'{0:F0}' -f ($d.FreeSpace/1MB)}" 2^>nul`) do set "PageFileFreeMB=%%A"

if not defined PageFileFreeMB (
    set "TBOK_PAGEFILE_NAME="
    call :LOG ERROR: Free space on the selected page-file drive could not be determined.
    call :LOG Page-file settings were left unchanged.
    goto :SERVICES
)

:: Only the additional growth requires new free space.
set /a "PageFileGrowthMB=PageFileMaximumMB-PageFileCurrentMaximumMB"

if !PageFileGrowthMB! LSS 0 set "PageFileGrowthMB=0"

set /a "PageFileRequiredMB=PageFileGrowthMB+1024"

call :LOG Available drive space: !PageFileFreeMB! MB
call :LOG Required additional space including reserve: !PageFileRequiredMB! MB

if !PageFileFreeMB! LSS !PageFileRequiredMB! (
    set "TBOK_PAGEFILE_NAME="
    call :LOG ERROR: Insufficient free space for the requested page-file maximum.
    call :LOG Page-file settings were left unchanged.
    goto :SERVICES
)

:: Export simple values for the short configuration commands.
set "TBOK_PAGEFILE_INITIAL=!PageFileInitialMB!"
set "TBOK_PAGEFILE_MAXIMUM=!PageFileMaximumMB!"

if !PageFileSettingCount! GTR 0 goto :UpdateExistingPageFile
goto :CreateExplicitPageFile

:UpdateExistingPageFile
if "!PageFileCurrentInitialMB!"=="!PageFileInitialMB!" if "!PageFileCurrentMaximumMB!"=="!PageFileMaximumMB!" (
    call :LOG The page file is already configured correctly.
    set "PageFileRC=0"
    goto :PageFileComplete
)

powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$p=Get-CimInstance Win32_PageFileSetting -Filter ('Name='''+$env:TBOK_PAGEFILE_NAME.Replace('\','\\')+'''') -ErrorAction Stop;Set-CimInstance -InputObject $p -Property @{InitialSize=[uint32]$env:TBOK_PAGEFILE_INITIAL;MaximumSize=[uint32]$env:TBOK_PAGEFILE_MAXIMUM} -ErrorAction Stop | Out-Null;exit 0}catch{Write-Output ('ERROR: '+$_.Exception.Message);exit 1}" >>"%LOGFILE%" 2>&1

set "PageFileRC=!ERRORLEVEL!"

if "!PageFileRC!"=="0" (
    call :LOG Page-file sizes were updated. A restart is required.
)
goto :PageFileComplete

:CreateExplicitPageFile
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$c=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop;$changed=$false;if($c.AutomaticManagedPagefile){Set-CimInstance -InputObject $c -Property @{AutomaticManagedPagefile=$false} -ErrorAction Stop | Out-Null;$changed=$true};try{New-CimInstance Win32_PageFileSetting -Property @{Name=$env:TBOK_PAGEFILE_NAME;InitialSize=[uint32]$env:TBOK_PAGEFILE_INITIAL;MaximumSize=[uint32]$env:TBOK_PAGEFILE_MAXIMUM} -ErrorAction Stop | Out-Null}catch{if($changed){$c=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue;if($c){Set-CimInstance -InputObject $c -Property @{AutomaticManagedPagefile=$true} -ErrorAction SilentlyContinue | Out-Null}};throw};exit 0}catch{Write-Output ('ERROR: '+$_.Exception.Message);exit 1}" >>"%LOGFILE%" 2>&1

set "PageFileRC=!ERRORLEVEL!"

if "!PageFileRC!"=="0" (
    call :LOG An explicit page-file setting was created. A restart is required.
)

:PageFileComplete
set "TBOK_PAGEFILE_NAME="
set "TBOK_PAGEFILE_INITIAL="
set "TBOK_PAGEFILE_MAXIMUM="

if "!PageFileRC!"=="0" (
    call :LOG Virtual-memory configuration completed successfully.
) else (
    call :LOG ERROR: Virtual-memory configuration failed with exit code !PageFileRC!.
)

ECHO.

:SERVICES
::Configure Windows system services to an optimized state
:svcHostThresholdStart
call :LOG Enable Modern SvHost split process grouping behaviour according to currently installed RAM
call :LOG This changes the svhost process grouping to an optimized state based on installed RAM
call :LOG Works up to around 4TB of RAM - after that there's no noticeable improvement
::This changes how many processes are grouped according to available memory - it does not actually reduce running processes
set "MemoryKB=!TBOK_MEMORY_KB!"
set "SvcHostThresholdKB="
if not defined MemoryKB (
    call :LOG WARNING: Unable to determine installed RAM. SvcHostSplitThresholdInKB was not changed.
    goto :SvcHostThresholdComplete
)
call :LOG Installed RAM: !MemoryKB! KB
set "TBOK_SVCHOST_MEMORY_KB=!MemoryKB!"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$n=[uint64]$env:TBOK_SVCHOST_MEMORY_KB+262144;if($n -gt 4294967295){$n=4294967295};[uint64]$n" 2^>nul`) do (
    set "SvcHostThresholdKB=%%A"
)
set "TBOK_SVCHOST_MEMORY_KB="
if not defined SvcHostThresholdKB (
    call :LOG ERROR: Could not calculate SvcHostSplitThresholdInKB.
    goto :SvcHostThresholdComplete
)
call :SetAllControlSetValues "Control" "SvcHostSplitThresholdInKB" "REG_DWORD" "!SvcHostThresholdKB!" "SvcHostSplitThresholdInKB"
:svcHostThresholdComplete

:windowsservicedisable
ECHO.
ECHO.
call :LOG Setting Windows Services to Optimized State
ECHO.
call :LOG **********************************************************
call :LOG              Starting Services Optimizations             
call :LOG **********************************************************

call :LOG Disabling services that are not used or should be disabled
::deprecated means service not in current versions of windows 10 or 11pro-ent-ltsc
::deprecated call :SetServiceStartup AJRouter disabled
call :SetServiceStartup AppVClient disabled
call :SetServiceStartup NetTcpPortSharing disabled
call :SetServiceStartup DialogBlockingService disabled
call :SetServiceStartup DiagTrack disabled
call :SetServiceStartup UevAgentService disabled
call :SetServiceStartup ssh-agent disabled

call :LOG Applying the resolved SysMain and MMAgent service policy
:: TBOK low-memory policy:
:: Systems with 12 GB or less RAM keep SysMain Automatic and running so
:: Memory Compression, Page Combining, and the MMAgent workers remain available.
:: Higher-memory SSD systems disable SysMain.
:: Higher-memory HDD systems set SysMain to Demand.
:: Higher-memory systems with unknown storage leave SysMain unchanged.
call :LOG Installed RAM: !TBOK_MEMORY_MB! MB
call :LOG Storage profile: !TBOK_DRIVETYPE!
call :LOG Low-memory profile: !TBOK_LOW_MEMORY!
call :LOG SysMain target mode: !TBOK_SYSMAIN_MODE!

if /I "!TBOK_SYSMAIN_MODE!"=="auto" (
    call :LOG Keeping SysMain Automatic so low-memory MMAgent features remain available.
    call :SetServiceStartup SysMain auto
) else if /I "!TBOK_SYSMAIN_MODE!"=="disabled" (
    call :LOG Disabling SysMain on this higher-memory SSD system.
    call :SetServiceStartup SysMain disabled
) else if /I "!TBOK_SYSMAIN_MODE!"=="demand" (
    call :LOG Setting SysMain to start on demand on this higher-memory HDD system.
    call :SetServiceStartup SysMain demand
) else (
    call :LOG SysMain and MMAgent were left unchanged because no reliable target mode was resolved.
)
ECHO.
call :LOG Done with services to disable
ECHO.
:windowsservicedemand
call :LOG Setting non-critical Windows services to manual startup 
call :LOG They still function when needed but are not auto running on startup
call :LOG Many of these are manual by default anyway -FYI
call :LOG Some of this process is just to restore that behaviour in case something changed them
call :SetServiceStartup ALG demand
::protectedCOREservice call :SetServiceStartup AppIDSvc demand
call :SetServiceStartup AppMgmt demand
call :SetServiceStartup AppReadiness demand
call :SetServiceStartup Appinfo demand
call :SetServiceStartup AssignedAccessManagerSvc demand
call :SetServiceStartup AxInstSV demand
call :SetServiceStartup BDESVC demand
::ignored call :SetServiceStartup BcastDVRUserService_* demand
::ignored call :SetServiceStartup BluetoothUserService_* demand
::deprecated call :SetServiceStartup 'Browser' demand
call :SetServiceStartup BTAGService demand
call :SetServiceStartup bthserv demand
::ignored call :SetServiceStartup CaptureService_* demand
::ignored call :SetServiceStartup cbdhsvc_* demand
::deprecated call :SetServiceStartup CDPSvc demand
call :SetServiceStartup CertPropSvc demand
call :SetServiceStartup cloudidsvc demand
call :SetServiceStartup COMSysApp demand
::protectedCOREservice call :SetServiceStartup ClipSVC demand
::ignored call :SetServiceStartup ConsentUxUserSvc_* demand
::ignored call :SetServiceStartup CredentialEnrollmentManagerUserSvc_* demand
call :SetServiceStartup CscService demand
call :SetServiceStartup DcpSvc demand
call :SetServiceStartup dcsvc demand
call :SetServiceStartup defragsvc demand
call :SetServiceStartup DevQueryBroker demand
::ignored call :SetServiceStartup DeviceAssociationBroker_* demand
call :SetServiceStartup DeviceAssociationService demand
call :SetServiceStartup DeviceInstall demand
::ignored call :SetServiceStartup DevicePickerUserSvc_* demand
::ignored call :SetServiceStartup DevicesFlowUserSvc_* demand
call :SetServiceStartup diagnosticshub.standardcollector.service demand
call :SetServiceStartup diagsvc demand
call :SetServiceStartup DisplayEnhancementService demand
call :SetServiceStartup DmEnrollmentSvc demand
call :SetServiceStartup dmwappushservice demand
call :SetServiceStartup dot3svc demand
::protectedCOREservice call :SetServiceStartup DoSvc demand
::protectedCOREservice call :SetServiceStartup embeddedmode demand
call :SetServiceStartup fdPHost demand
call :SetServiceStartup fhsvc demand
call :SetServiceStartup hidserv demand
call :SetServiceStartup icssvc demand
call :SetServiceStartup EapHost demand
call :SetServiceStartup edgeupdate demand
call :SetServiceStartup edgeupdatem demand
call :SetServiceStartup EFS demand
::protectedCOREservice call :SetServiceStartup EntAppSvc demand
call :SetServiceStartup FDResPub demand
call :SetServiceStartup Fax demand
call :SetServiceStartup FrameServer demand
call :SetServiceStartup FrameServerMonitor demand
call :SetServiceStartup GraphicsPerfSvc demand
::deprecated call :SetServiceStartup  HomeGroupListener demand
::deprecated call :SetServiceStartup  HomeGroupProvider demand
call :SetServiceStartup HvHost demand
call :SetServiceStartup IEEtwCollectorService demand
::omitforEnterprise IPsec and VPN call :SetServiceStartup IKEEXT demand
::ignored call :SetServiceStartup InstallService demand
call :SetServiceStartup IpxlatCfgSvc demand
call :SetServiceStartup lfsvc demand
::ignored call :SetServiceStartup LicenseManager demand
call :SetServiceStartup lltdsvc demand
call :SetServiceStartup lmhosts demand
call :SetServiceStartup LxpSvc demand
call :SetServiceStartup McpManagementService demand
::ignored call :SetServiceStartup MessagingService_* demand
call :SetServiceStartup MicrosoftEdgeElevationService demand
call :SetServiceStartup MixedRealityOpenXRSvc demand
call :SetServiceStartup MSDTC demand
call :SetServiceStartup MsKeyboardFilter demand
call :SetServiceStartup MSiSCSI demand
::protectedCOREservice call :SetServiceStartup msiserver demand
::ignored call :SetServiceStartup NPSMSvc_* demand
call :SetServiceStartup NaturalAuthentication demand
call :SetServiceStartup NcaSvc demand
call :SetServiceStartup NcbService demand
call :SetServiceStartup NcdAutoSetup demand
call :SetServiceStartup NetSetupSvc demand
call :SetServiceStartup Netman demand
::protectedCOREservice call :SetServiceStartup NgcCtnrSvc demand
::protectedCOREservice call :SetServiceStartup NgcSvc demand
::omitforENTERPRISE call :SetServiceStartup NlaSvc demand
::omitforENTERPRISE call :SetServiceStartup netprofm demand
call :SetServiceStartup p2pimsvc demand
call :SetServiceStartup p2psvc demand
::ignored call :SetServiceStartup P9RdrService_* demand
call :SetServiceStartup PcaSvc demand
call :SetServiceStartup PeerDistSvc demand
::ignored call :SetServiceStartup PenService_* demand
call :SetServiceStartup perceptionsimulation demand
call :SetServiceStartup PerfHost demand
call :SetServiceStartup PhoneSvc demand
::ignored call :SetServiceStartup PimIndexMaintenanceSvc_* demand
call :SetServiceStartup pla demand
call :SetServiceStartup PlugPlay demand
call :SetServiceStartup PNRPAutoReg demand
call :SetServiceStartup PNRPsvc demand
call :SetServiceStartup PolicyAgent demand
call :SetServiceStartup PrintNotify demand
::ignored call :SetServiceStartup PrintWorkflowUserSvc_* demand
call :SetServiceStartup PushToInstall demand
call :SetServiceStartup QWAVE demand
call :SetServiceStartup RasAuto demand
call :SetServiceStartup RasMan demand
call :SetServiceStartup RetailDemo demand
call :SetServiceStartup RmSvc demand
call :SetServiceStartup RpcLocator demand
call :SetServiceStartup SCPolicySvc demand
call :SetServiceStartup ScDeviceEnum demand
call :SetServiceStartup SCardSvr demand
call :SetServiceStartup SDRSVC demand
call :SetServiceStartup seclogon demand
call :SetServiceStartup SEMgrSvc demand
call :SetServiceStartup SensorDataService demand
call :SetServiceStartup SensorService demand
call :SetServiceStartup SensrSvc demand
::omitforENTERPRISE RDP call :SetServiceStartup SessionEnv demand
call :SetServiceStartup SharedAccess demand
call :SetServiceStartup SharedRealitySvc demand
call :SetServiceStartup shpamsvc demand
call :SetServiceStartup SmsRouter demand
call :SetServiceStartup smphost demand
call :SetServiceStartup SNMPTrap demand
call :SetServiceStartup spectrum demand
call :SetServiceStartup SstpSvc demand
call :SetServiceStartup SSDPSRV demand
call :SetServiceStartup StiSvc demand
call :SetServiceStartup StorSvc demand
call :SetServiceStartup svsvc demand
call :SetServiceStartup swprv demand
::sysmain alphabetical placeholder
call :SetServiceStartup TabletInputService demand
call :SetServiceStartup TapiSrv demand
call :SetServiceStartup TieringEngineService demand
call :SetServiceStartup TimeBroker demand
::protectedCOREservice call :SetServiceStartup TimeBrokerSvc demand
::omitforENTERPRISE call :SetServiceStartup TokenBroker demand
call :SetServiceStartup TroubleshootingSvc demand
call :SetServiceStartup tzautoupdate demand
call :SetServiceStartup UI0Detect demand
::ignored call :SetServiceStartup UdkUserSvc_* demand
::omitforENTERPRISE RDP call :SetServiceStartup UmRdpService demand
::ignored call :SetServiceStartup UnistoreSvc_* demand
::ignored call :SetServiceStartup UserDataSvc_* demand
::omitforENTERPRISE call :SetServiceStartup UsoSvc demand
call :SetServiceStartup upnphost demand
call :SetServiceStartup VacSvc demand
call :SetServiceStartup vds demand
call :SetServiceStartup vmicguestinterface demand
call :SetServiceStartup vmicheartbeat demand
call :SetServiceStartup vmickvpexchange demand
::omitforENTERPRISE RDP call :SetServiceStartup vmicrdv demand
call :SetServiceStartup vmicshutdown demand
call :SetServiceStartup vmictimesync demand
call :SetServiceStartup vmicvmsession demand
call :SetServiceStartup vmicvss demand
call :SetServiceStartup VSS demand
call :SetServiceStartup WalletService demand
call :SetServiceStartup wbengine demand
call :SetServiceStartup WcsPlugInService demand
call :SetServiceStartup wcncsvc demand
::protectedCOREservice call :SetServiceStartup WdNisSvc demand
call :SetServiceStartup WdiServiceHost demand
call :SetServiceStartup WdiSystemHost demand
call :SetServiceStartup WebClient demand
call :SetServiceStartup Wecsvc demand
call :SetServiceStartup wercplsupport demand
call :SetServiceStartup WEPHOSTSVC demand
call :SetServiceStartup WerSvc demand
call :SetServiceStartup WFDSConMgrSvc demand
call :SetServiceStartup WiaRpc demand
::protectedCOREservice call :SetServiceStartup WinHttpAutoProxySvc demand
::omitforENTERPRISE call :SetServiceStartup WinRM demand
call :SetServiceStartup wisvc demand
call :SetServiceStartup wlidsvc demand
call :SetServiceStartup wlpasvc demand
call :SetServiceStartup wmiApSrv demand
call :SetServiceStartup WMPNetworkSvc demand
call :SetServiceStartup WManSvc demand
call :SetServiceStartup WPDBusEnum demand
call :SetServiceStartup WpcMonSvc demand
::omitforENTERPRISE call :SetServiceStartup WpnService demand
call :SetServiceStartup workfolderssvc demand
::deprecated call :SetServiceStartup  WSService demand
call :SetServiceStartup wuauserv demand
call :SetServiceStartup XblAuthManager demand
call :SetServiceStartup XblGameSave demand
call :SetServiceStartup XboxGipSvc demand
call :SetServiceStartup XboxNetApiSvc demand
ECHO.
call :LOG Done with manual services
:windowsserviceauto
ECHO.
call :LOG Ensuring required services are set to automatic State
call :LOG This is just in case you used a previous utility that set the services incorrectly
call :SetServiceStartup AudioEndpointBuilder auto
call :SetServiceStartup AudioSrv auto
::protectedCOREservice call :SetServiceStartup BFE auto
::protectedCOREservice call :SetServiceStartup BrokerInfrastructure auto
call :SetServiceStartup BthHFSrv auto
::ignored call :SetServiceStartup CDPUserSvc_* auto
::protectedCOREservice call :SetServiceStartup CoreMessagingRegistrar auto
call :SetServiceStartup CryptSvc auto
call :SetServiceStartup DPS auto
::protectedCOREservice call :SetServiceStartup DcomLaunch auto
call :SetServiceStartup Dhcp auto
call :SetServiceStartup DispBrokerDesktopSvc auto
::protectedCOREservice call :SetServiceStartup Dnscache auto
call :SetServiceStartup dusmsvc auto
call :SetServiceStartup EventLog auto
call :SetServiceStartup EventSystem auto
call :SetServiceStartup FontCache auto
::protectedCOREservice call :SetServiceStartup gpsvc auto
call :SetServiceStartup iphlpsvc auto
::protectedCOREservice call :SetServiceStartup LSM auto
call :SetServiceStartup LanmanServer auto
call :SetServiceStartup LanmanWorkstation auto
::protectedCOREservice call :SetServiceStartup MpsSvc auto
call :SetServiceStartup nsi auto
::ignored call :SetServiceStartup OneSyncSvc_* auto
call :SetServiceStartup Power auto
call :SetServiceStartup ProfSvc auto
::protectedCOREservice call :SetServiceStartup RpcEptMapper auto
::protectedCOREservice call :SetServiceStartup RpcSs auto
::omitforENTERPRISE call :SetServiceStartup RemoteAccess auto
::omitforENTERPRISE call :SetServiceStartup RemoteRegistry auto
call :SetServiceStartup SENS auto
call :SetServiceStartup SamSs auto
::protectedCOREservice call :SetServiceStartup Schedule auto
call :SetServiceStartup ShellHWDetection auto
call :SetServiceStartup Spooler auto
::protectedCOREservice call :SetServiceStartup sppsvc auto
::protectedCOREservice call :SetServiceStartup SystemEventsBroker auto
call :SetServiceStartup Themes auto
call :SetServiceStartup tiledatamodelsvc auto
call :SetServiceStartup TrkWks auto
call :SetServiceStartup uhssvc auto
call :SetServiceStartup UserManager auto
call :SetServiceStartup Wcmsvc auto
::ignore due to possible conflict with third-party antivitus call :SetServiceStartup WinDefend auto
call :SetServiceStartup Winmgmt auto
call :SetServiceStartup WlanSvc auto
::ignored call :SetServiceStartup WpnUserService_* auto
ECHO.
:windowsservicedelayed-auto
Call :LOG "Changing less essential services to delayed-auto"
call :SetServiceStartup BITS delayed-auto
::omit call :SetServiceStartup MapsBroker delayed-auto
::protectedCOREservice call :SetServiceStartup SecurityHealthService delayed-auto
call :SetServiceStartup W32Time delayed-auto
call :SetServiceStartup WSearch delayed-auto
::protectedCOREservice call :SetServiceStartup wscsvc delayed-auto
call :SetServiceStartup wudfsvc delayed-auto
ECHO.

call :ApplyServiceStartupPlan
set "ServiceBatchRC=!ERRORLEVEL!"

if "!ServiceBatchRC!"=="0" (
    call :LOG Windows Services Changes Completed successfully.
) else (
    call :LOG WARNING: The service section completed with one or more failures.
)
ECHO.
ECHO.

:machine-wide-registry
ECHO.

call :LOG ********************************************************************************
call :LOG        Enabling System-wide Registry Improvements
call :LOG ********************************************************************************
call :LOG 

call :LOG Disabling network throttling
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "REG_DWORD" "0xffffffff" "NetworkThrottlingIndex"

call :LOG Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
call :SetAllControlSetValues "Services\LanmanServer\Parameters" "IRPStackSize" "REG_DWORD" "30" "IRPStackSize"

call :LOG Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" "REG_DWORD" "10" "SystemResponsiveness"

call :LOG Speed up shutdown time
call :SetAllControlSetValues "Control" "WaitToKillServiceTimeout" "REG_SZ" "5000" "WaitToKillServiceTimeout"

call :LOG Enabling long file system path support -why is this disabled by default Microsoft
call :SetAllControlSetValues "Control\FileSystem" "LongPathsEnabled" "REG_DWORD" "1" "LongPathsEnabled"

call :LOG Disabling the setting allowing hardware to install whatever software addon - LG Monitor McAffee Incident
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" "PreventDeviceMetadataFromNetwork" "REG_DWORD" "1" "PreventDeviceMetadataFromNetwork"

call :LOG Disable Webview dependency for Search - breaks nothing - puts search back into classic mode
call :SetAllControlSetValues "Control\FeatureManagement\Overrides\8\1694661260" "EnabledState" "REG_DWORD" "1" "Search WebView override EnabledState"
call :SetAllControlSetValues "Control\FeatureManagement\Overrides\8\1694661260" "EnabledStateOptions" "REG_DWORD" "0" "Search WebView override EnabledStateOptions"
call :SetAllControlSetValues "Control\FeatureManagement\Overrides\8\1694661260" "Variant" "REG_DWORD" "0" "Search WebView override Variant"
call :SetAllControlSetValues "Control\FeatureManagement\Overrides\8\1694661260" "VariantPayload" "REG_DWORD" "0" "Search WebView override VariantPayload"
call :SetAllControlSetValues "Control\FeatureManagement\Overrides\8\1694661260" "VariantPayloadKind" "REG_DWORD" "0" "Search WebView override VariantPayloadKind"

::Control OOBE experience for new users or major updates-testing needed to confirm but it is documented
call :LOG Disable privacy settings experience at first OOBE logon
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "DisablePrivacyExperience" "REG_DWORD" "1" "OOBE policy DisablePrivacyExperience"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "BypassNRO" "REG_DWORD" "1" "BypassNRO policy"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "SkipMachineOOBE" "REG_DWORD" "1" "SkipMachineOOBE"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "DisableVoice" "REG_DWORD" "1" "DisableVoice"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "PrivacyConsentStatus" "REG_DWORD" "1" "PrivacyConsentStatus"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "Protectyourpc" "REG_DWORD" "3" "ProtectYourPC"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "HideEULAPage" "REG_DWORD" "1" "HideEULAPage"

call :LOG Restore the lock screen now that personalized ads are removed.
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" "REG_DWORD" "0" "NoLockScreen"

call :LOG Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
call :SetAllControlSetValues "Control\Session Manager" "DisableWpbtExecution" "REG_DWORD" "1" "DisableWpbtExecution"

call :SetAllControlSetValues "Control\FirmwareResources" "WPBT" "REG_BINARY" "00" "WPBT firmware resource value"

call :LOG Fix Network Data Usage Graph not working
call :SetAllControlSetValues "Services\Ndu" "Start" "REG_DWORD" "2" "Ndu service startup mode"

call :LOG Limiting Microsoft Defender scan CPU usage during scheduled and manual scans only - realtime protection is unaffected.
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" "ScanAvgCPULoadFactor" "REG_DWORD" "25" "Defender ScanAvgCPULoadFactor"

call :LOG Configuring Storage Sense for automatic disk cleanup in low disk space conditions
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "AllowStorageSenseGlobal" "REG_DWORD" "1" "AllowStorageSenseGlobal"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "AllowStorageSenseTemporaryFilesCleanup" "REG_DWORD" "1" "AllowStorageSenseTemporaryFilesCleanup"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "ConfigStorageSenseGlobalCadence" "REG_DWORD" "0" "Storage Sense cadence"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "ConfigStorageSenseRecycleBinCleanupThreshold" "REG_DWORD" "30" "Recycle Bin cleanup threshold"
::call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "ConfigStorageSenseGlobalCadence" "REG_DWORD" "30" "Storage Sense monthly cadence"
call :LOG Storage Sense enabled with temporary-file cleanup when disk space is low.

:systemtelemetry
call :LOG Disabling Windows System Telemetry Data Collection through Registry
call :LOG Turning off telemetry data collection Local Machine
call :SetAllControlSetValues "Control\WMI\AutoLogger\Diagtrack-Listener" "Start" "REG_DWORD" "0" "Diagtrack-Listener AutoLogger startup mode"
call :SetAllControlSetValues "Services\DiagTrack" "Start" "REG_DWORD" "4" "DiagTrack service startup mode"
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Windows\DataCollection" "AllowDesktopAnalyticsProcessing" "REG_DWORD" "0" "AllowDesktopAnalyticsProcessing"
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "REG_DWORD" "0" "DataCollection policy AllowTelemetry"
call :SetRegistryValue "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "REG_DWORD" "0" "Wow6432Node DataCollection policy AllowTelemetry"
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" "REG_DWORD" "0" "CurrentVersion DataCollection AllowTelemetry"
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" "REG_DWORD" "1" "DoNotShowFeedbackNotifications"
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Windows\DataCollection" "DiagTrack" "REG_DWORD" "0" "DiagTrack"
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Windows\DataCollection" "LimitEnhancedDiagnosticDataWindowsAnalytics" "REG_DWORD" "1" "LimitEnhancedDiagnosticDataWindowsAnalytics"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" "REG_DWORD" "1" "DisabledByGroupPolicy"
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" "Disabled" "REG_DWORD" "1" "Disable Error Reporting"

call :LOG Disable Powershell telemetry
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" "REG_DWORD" "1" "DisableAIDataAnalysis"

call :LOG Disabling Windows Updated DeliveryOptimization network bandwidth use through Registry
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" "DODownloadMode" "REG_DWORD" "0" "Current Version Delivery Optimization Config DODownloadMode"

call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" "REG_DWORD" "0" "Delivery Optimization policy DODownloadMode"

call :LOG Disabling Windows Feeds through machine policy
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" "REG_DWORD" "0" "Machine policy EnableFeeds"

:EdgeTweaks
call :LOG Disabling MS Edge Automatic Background Startup
call :LOG Disable Edge so-called start boost - Edge runs on startup even if you dont use it
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "StartupBoostEnabled" "REG_DWORD" "0" "StartupBoostEnabled"

call :LOG Enabling Edge Efficiency Mode to save resources (is not enabled by default on desktops)
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Edge" "EfficiencyModeEnabled" "REG_DWORD" "1" "Edge Efficiency Mode Enabled"

call :LOG Enable Edge Sleeping tabs when they are idle
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Edge" "SleepingTabsEnabled" "REG_DWORD" "1" "Edge Sleeping Tabs"
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Edge" "SleepingTabsTimeout" "REG_DWORD" "900" "Edge Sleeping Tabs Timeout"

call :LOG Disable MS Edge from running in the background after close
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "BackgroundModeEnabled" "REG_DWORD" "0" "BackgroundModeEnabled"

call :LOG Disable MS Edge exhaustive Edge first run experience
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "HideFirstRunExperience" "REG_DWORD" "1" "HideFirstRunExperience"

call :LOG Disabling MS Edge submit user feedback
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "UserFeedbackAllowed" "REG_DWORD" "0" "UserFeedbackAllowed"

call :LOG Disabling MS Edge shopping assistant ads
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "EdgeShoppingAssistantEnabled" "REG_DWORD" "0" "EdgeShoppingAssistantEnabled"

call :LOG Enabling MS Edge PC gaming mode for lower CPU usage while Gaming
::While this serves to lower CPU resource usage for the browser - it also monitors everything running
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "GamerModeEnabled" "REG_DWORD" "1" "GamerModeEnabled"

call :LOG Disable MS Edge Sending Browser Usage DiagnosticData 0
call :SetRegistryValue "HKLM\Software\Policies\Microsoft\Edge" "DiagnosticData" "REG_DWORD" "0" "DiagnosticData"

call :LOG Disabling Microsoft Recall from being enabled
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement" "REG_DWORD" "0" "AllowRecallEnablement"

call :LOG Optional:Enable verbose logon-off status on screen 
call :LOG replaces windows starting and shutting down messages with what its actually doing
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "VerboseStatus" "REG_DWORD" "1" "VerboseStatus"

::call :LOG Wi-Fi Sense Disable affects devices autoconnecting - leaving enabled
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1

::call :LOG Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f >>"%LOGFILE%" 2>&1

::call :LOG Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has an unfixed known vulnerability
::Microsoft protected these keys from being modified in an update
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1

::Optional For system hardening only - Clear pagefile at shutdown
:: sometimes slows shutdown time removing sensitive memory remnants from pagefile.sys - rebuilds each boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1

::call :LOG Disable GameDVR - not recommended on AMD X3d chips due to CCD cache routing
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1

::Disable Windows Code Integrity app control - SmartAPPControl
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1

::Allow RDP remote assistance - leave enabled for business use
::call :SetRegistryValue "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" "fAllowToGetHelp" "REG_DWORD" "0" "for %BASE%"


:DEBLOAT
call :LOG System level registry tweaks completed
ECHO.
ECHO.
call :LOG **********************************************************
call :LOG               Time for some bloat removal                
call :LOG **********************************************************
ECHO.
call :BuildAppxInventory

call :LOG Remove and Disable Windows CoPilot -standard version NOT M365 CoPilot- machine wide
::Enable reg key that allows app to be disabled or uninstalled systemwide
call :SetRegistryValue "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "REG_DWORD" "1" "TurnOffWindowsCopilot"

call :LOG Removing existing Microsoft Co-Pilot installed package
call :ProcessInstalledAppxPattern "*Microsoft.Copilot*" "Microsoft Copilot"

call :LOG Removing provisioned Microsoft Co-Pilot installed package
call :ProcessProvisionedAppxPattern "*Microsoft.Copilot*" "Microsoft Copilot"

call :LOG Configuring registry keys to prevent reinstallation through future updates. Does not affect M365 CoPilot
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" "IsCopilotAvailable" "REG_DWORD" "0" "IsCopilotAvailable"

call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" "CopilotDisabledReason" "REG_SZ" "IsEnabledForGeographicRegionFailed" "CopilotDisabledReason"

call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}" "REG_SZ" "1" "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}"

call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" "IsUserEligible" "REG_DWORD" "0" "IsUserEligible"


call :LOG Removing Bing Search
call :LOG Removing installed Microsoft Bing Search packages...
call :ProcessInstalledAppxPattern "*Microsoft.BingSearch*" "Microsoft Bing Search"

call :LOG Removing provisioned Microsoft Bing Search packages...
call :ProcessProvisionedAppxPattern "*Microsoft.BingSearch*" "Microsoft Bing Search"

call :LOG Removing Taskbar Widgets that should have died with Vista because now they run an entire chromium browser process
call :LOG Stopping running Windows Widgets processes...

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $processes = @(Get-Process -Name '*Widget*' -ErrorAction SilentlyContinue);" ^
    "    if ($processes.Count -eq 0) {" ^
    "        Write-Output 'SKIPPED: No running Widgets processes found.';" ^
    "    } else {" ^
    "        $processes | Stop-Process -Force -ErrorAction Stop;" ^
    "        Write-Output ('SUCCESS: Stopped ' + $processes.Count + ' Widgets process(es).');" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Failed to stop Widgets processes: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

if errorlevel 1 (
    call :LOG WARNING: One or more Widgets processes could not be stopped.
)
call :LOG Removing installed Microsoft Widgets Platform Runtime packages...
call :ProcessInstalledAppxPattern "Microsoft.WidgetsPlatformRuntime" "Microsoft Widgets Platform Runtime"

call :LOG Removing provisioned Microsoft Widgets Platform Runtime packages...
call :ProcessProvisionedAppxPattern "*Microsoft.WidgetsPlatformRuntime*" "Microsoft Widgets Platform Runtime"

call :LOG Removing installed Microsoft WebExperience packages...
call :ProcessInstalledAppxPattern "MicrosoftWindows.Client.WebExperience" "Windows Web Experience"

call :LOG Removing provisioned Windows Web Experience packages...
call :ProcessProvisionedAppxPattern "*MicrosoftWindows.Client.WebExperience*" "Windows Web Experience"

:DeleteScheduledTasks
call :LOG **********************************************************
call :LOG           Removing Telemetry Scheduled Tasks                
call :LOG **********************************************************
::==Remove wasteful Scheduled Tasks==
:officetelemetrytasks
call :LOG Disabling wasteful scheduled tasks
:: =======Disable Microsoft Office telemetry agent==========
call :LOG Disabling Microsoft Office 14-16 telemetry scheduled tasks -if found...

call :DisableTask "\Microsoft\Office\" "OfficeTelemetryAgent"
if errorlevel 1 call :LOG WARNING: Failed to disable OfficeTelemetryAgent.

call :DisableTask "\Microsoft\Office\" "OfficeTelemetryAgentFallBack"
if errorlevel 1 call :LOG WARNING: Failed to disable OfficeTelemetryAgentFallBack.

call :DisableTask "\Microsoft\Office\" "OfficeTelemetryAgentLogon"
if errorlevel 1 call :LOG WARNING: Failed to disable OfficeTelemetryAgentLogon.

call :DisableTask "\Microsoft\Office\" "OfficeTelemetryAgentFallBack2016"
if errorlevel 1 call :LOG WARNING: Failed to disable OfficeTelemetryAgentFallBack2016.

call :DisableTask "\Microsoft\Office\" "OfficeTelemetryAgentLogOn2016"
if errorlevel 1 call :LOG WARNING: Failed to disable OfficeTelemetryAgentLogOn2016.

:windowsTasks
call :LOG Disabling wasteful windows tasks
::customer experience improvement program tasks that run even if not joined in the program
call :DisableTask "\Microsoft\Windows\Application Experience\" "Microsoft Compatibility Appraiser"
if errorlevel 1 call :LOG WARNING: Failed to disable Microsoft Compatibility Appraiser.
::these next ones are ok because they download app compatibility information, not send
::call :DisableTask "Microsoft\Windows\Application Experience\" "ProgramDataUpdater"
::if errorlevel 1 call :LOG WARNING: Failed to disable ProgramDataUpdater.
::call :DisableTask "Microsoft\Windows\Application Experience\" "MareBackup"
::if errorlevel 1 call :LOG WARNING: Failed to disable MareBackup.
::*StartupAppTask below is useful because it notifies users when they have too many startup apps
::call :DisableTask "Microsoft\Windows\Application Experience\"  "StartupAppTask"
::if errorlevel 1 call :LOG WARNING: Failed to disable StartupAppTask.
::pcaPatchDbTask below updates the local database of what apps need to run in compatibility mode
::call :DisableTask "Microsoft\Windows\Application Experience\" "PcaPatchDbTask"
::if errorlevel 1 call :LOG WARNING: Failed to disable PcaPatchDbTask.
call :DisableTask "\Microsoft\Windows\Autochk\" "Proxy"
if errorlevel 1 call :LOG WARNING: Failed to disable Proxy.
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\" "Consolidator"
if errorlevel 1 call :LOG WARNING: Failed to disable Consolidator.
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\" "UsbCeip"
if errorlevel 1 call :LOG WARNING: Failed to disable UsbCeip.
call :DisableTask "\Microsoft\Windows\DiskDiagnostic\" "Microsoft-Windows-DiskDiagnosticDataCollector"
if errorlevel 1 call :LOG WARNING: Failed to disable Microsoft-Windows-DiskDiagnosticDataCollector.

::Microsoft Windows Feedback application background application collector
call :DisableTask "\Microsoft\Windows\Feedback\Siuf\" "DmClient"
if errorlevel 1 call :LOG WARNING: Failed to disable DmClient.
call :DisableTask "\Microsoft\Windows\Feedback\Siuf\" "DmClientOnScenarioDownload"
if errorlevel 1 call :LOG WARNING: Failed to disable DmClientOnScenarioDownload.

::Microsoft MAPS download task -runs hourly to update offline maps but found it runs even if you never use maps
call :DisableTask "\Microsoft\Windows\Maps\" "MapsUpdateTask"
if errorlevel 1 call :LOG WARNING: Failed to disable MapsUpdateTask.

::Windows Error reporting upload - runs at startup and ran again consistently 31 times per day on average
call :DisableTask "\Microsoft\Windows\Windows Error Reporting\" "QueueReporting"
if errorlevel 1 call :LOG WARNING: Failed to disable QueueReporting.

call :ApplyTaskPlan
if errorlevel 1 (
    call :LOG WARNING: One or more scheduled-task changes failed.
) else (
    call :LOG Scheduled-task processing completed successfully.
)

::ENABLE THIS Task and test how annoying it would be. Linux notifies the user when their drive is about to die, why not windows
::Notifies you when your hard drive reports faults in S.M.A.R.T. data at logon - help in data loss prevention
::call :EnableTask "Microsoft\Windows\DiskDiagnostic\" "Microsoft-Windows-DiskDiagnosticResolver"
::if errorlevel 1 call :LOG WARNING: Failed to disable Microsoft-Windows-DiskDiagnosticDataCollector.


:USERTWEAKS
call :LOG **********************************************************
call :LOG        Enabling User-level Registry Improvements        
call :LOG **********************************************************
goto UserRegistryDeployment
:: ===============================================================
:: -START SECTION - APPLY PER USER REGISTRY SETTINGS TO ALL USERS
:: ===============================================================
:: PER USER REGISTRY KEYS TO APPLY - This section applies registry tweaks
:: This will loop through each existing user account on the pc and apply the registry settings below 


:ApplySettings
call :LOG ========= Apply Tweaks to User Registry Hives and Default ==============
set "BASE=%~1"
if not defined BASE (
    call :LOG ERROR: ApplySettings called with no registry hive.
    exit /b 2
)
call :LOG *****************************************************************
call :LOG Applying User Registry settings to %BASE%
call :LOG *****************************************************************
::***********************************************USER HKCU REGISTRY KEYS*******************************************

call :LOG Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
call :DeleteRegistryKeyIfPresent "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" "Explorer Bags for %BASE%"
call :DeleteRegistryKeyIfPresent "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" "Explorer BagMRU for %BASE%"
call :EnsureRegistryKey "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" "Explorer AllFolders Shell key for %BASE%"

call :SetRegistryValueQuiet "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" "FolderType" "REG_SZ" "NotSpecified" "Explorer AllFolders FolderType for %BASE%"

call :LOG Preference- Default Explorer to open at "This PC" as default instead of the quick menu
::--1 - fastest load --2 is default quick access - and 3 is downloads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" "REG_DWORD" "1" "Explorer LaunchTo for %BASE%"

call :LOG Disabling allowing Windows apps to run in the background systemwide
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" "REG_DWORD" "1" "GlobalUserDisabled for %BASE%"

call :LOG Enabling Game Mode always on which helps reduce background system resource usage
::uses ~14mb ram but helps Processors with CCD technology and e-core parking
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\GameBar" "AutoGameModeEnabled" "REG_DWORD" "1" "AutoGameModeEnabled for %BASE%"

call :LOG Preference -Enabling end task from Taskbar - super useful to avoid opening task manager just to end a stalled app
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" "REG_DWORD" "1" "TaskbarEndTask for %BASE%"

call :LOG Preference -Enabling show full right-click context menus in Windows 11
call :EnsureRegistryKey "%BASE%\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "Classic context-menu InprocServer32 key for %BASE%"

call :LOG Disabling bing search in start menu -keep the start menu local
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" "REG_DWORD" "0" "BingSearchEnabled for %BASE%"

call :LOG Enable allow Pinning more apps on the start menu for less wasted space -such a big start menu
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_Layout" "REG_DWORD" "1" "Start_Layout Expanded Pinning for %BASE%"


call :LOG Setting speed up menu show delay - Windows default is 400ms - why wait so long
call :SetRegistryValueQuiet "%BASE%\Control Panel\Desktop" "MenuShowDelay" "REG_SZ" "10" "MenuShowDelay 10ms for %BASE%"

call :LOG Disabling some gaudy resource consuming desktop visual effects -explorer
call :LOG Setting visual effects setting to custom
:: 3 is custom - default 0 - 1 best appearance - 2 best performance but takes windows look to 1990
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" "REG_DWORD" "3" "VisualFXSetting for %BASE%"

::disable taskbar animations
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" "REG_DWORD" "0" "TaskbarAnimations for %BASE%"

::copilot icon in taskbar
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAI" "REG_DWORD" "0" "TaskbarAI for %BASE%"
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" "REG_DWORD" "0" "ShowCopilotButton for %BASE%"

::Enable alpha blending selection
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" "REG_DWORD" "1" "ListViewAlphaSelect for %BASE%"

::Enable list view shadows
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" "REG_DWORD" "1" "ListViewShadow for %BASE%"

::Disable the people icon on the taskbar
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" "REG_DWORD" "0" "TaskbarMn for %BASE%"

::Enable dragging full windows instead of just the frame
call :SetRegistryValueQuiet "%BASE%\Control Panel\Desktop" "DragFullWindows" "REG_SZ" "1" "DragFullWindows for %BASE%"

::Set the minimum animation speed to 0 for disable
call :SetRegistryValueQuiet "%BASE%\Control Panel\Desktop\WindowMetrics" "MinAnimate" "REG_SZ" "0" "MinAnimate for %BASE%"

::Disable keyboard input delay
call :SetRegistryValueQuiet "%BASE%\Control Panel\Keyboard" "KeyboardDelay" "REG_SZ" "0" "KeyboardDelay for %BASE%"

::Disable Windows Aero Peek
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "REG_DWORD" "0" "DisableAeroPeek for %BASE%"

::Optional Preference Taskbar StartMenu alignment left
::call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" "REG_DWORD" "0" "TaskBarAlignment for %BASE%"

::call :LOG Disable transparency effects - optional - left enabled for WindHawk TransparentTB and WallpaperEngine
::call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency "REG_DWORD" "0" "EnableTransparency for %BASE%"

::research this - possible webview dependency removal - found all over the place - runaway webview2.exe processes
::call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "WebView" "REG_DWORD" "0" "Webview for %BASE%

:advertising
call :LOG Start Disabling User level ads in Windows

call :LOG Disable Explorer search box suggestions -Ads-
call :SetRegistryValueQuiet "%BASE%\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" "REG_DWORD" "1" "DisableSearchBoxSuggestions for %BASE%"

call :LOG Disabling file explorer ads
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" "REG_DWORD" "0" "ShowSyncProviderNotifications for %BASE%"

call :LOG Disabling Account ads - This one Microsoft might change as it is relatively new
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_AccountNotifications" "REG_DWORD" "0" "Start_AccountNotifications for %BASE%"

call :LOG Disable recurring finish setup ads named "Suggest ways to get the most out of Windows"
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" "REG_DWORD" "0" "ScoobeSystemSettingEnabled for %BASE%"

call :LOG Disabling lock screen tips and ads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" "REG_DWORD" "0" "RotatingLockScreenOverlayEnabled for %BASE%"

call :LOG Disabling personalized ads
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "REG_DWORD" "0" "AdvertisingInfo Disabled for %BASE%"

call :LOG Disabling welcome experience ads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" "REG_DWORD" "0" "SubscribedContent-310093Enabled for %BASE%"

call :LOG Disabling settings ads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" "REG_DWORD" "0" "SubscribedContent-338387Enabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" "REG_DWORD" "0" "SubscribedContent-353694Enabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" "REG_DWORD" "0" "SubscribedContent-353696Enabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "REG_DWORD" "0" "SystemPaneSuggestionsEnabled for %BASE%"


call :LOG Disabling auto install of suggested apps - "Get more out of windows" ad space
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" "REG_DWORD" "0" "SubscribedContent-338388Enabled for %BASE%"

call :LOG Disabling general tips and ads - why are these together Microslop
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" "REG_DWORD" "0" "SubscribedContent-338389Enabled for %BASE%"

call :LOG Disabling home screen ads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338393Enabled" "REG_DWORD" "0" "SubscribedContent-338393Enabled for %BASE%"

call :LOG Disabling Timeline Suggestions ads
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353698Enabled" "REG_DWORD" "0" "SubscribedContent-353698Enabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" "REG_DWORD" "0" "SilentInstalledAppsEnabled for %BASE%"


call :LOG Disable Windows Content Delivery
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "ContentDeliveryAllowed" "REG_DWORD" "0" "ContentDeliveryAllowed for %BASE%"

call :LOG Disable automatic enabling of OEM and Preinstalled apps
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "OemPreInstalledAppsEnabled" "REG_DWORD" "0" "OemPreInstalledAppsEnabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEnabled" "REG_DWORD" "0" "PreInstalledAppsEnabled for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEverEnabled" "REG_DWORD" "0" "PreInstalledAppsEverEnabled for %BASE%"

::Windows Diagnostics Feedback request frequency
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" "REG_DWORD" "0" "NumberOfSIUFInPeriod for %BASE%"
call :DeleteRegistryValueIfPresent "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" "PeriodInNanoSeconds" "PeriodInNanoSeconds for %BASE%"
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" "REG_DWORD" "1" "DisableTailoredExperiencesWithDiagnosticData for %BASE%"

call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" "EnthusiastMode" "REG_DWORD" "1" "EnthusiastMode for %BASE%"

call :LOG Disabling start menu ads method 2
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_IrisRecommendations" "REG_DWORD" "0" "Start_IrisRecommendations %BASE%"

call :LOG Disabling tailored experiences with telemetry
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "REG_DWORD" "0" "TailoredExperiencesWithDiagnosticDataEnabled for %BASE%"

call :LOG Preference- Disable the TaskView button in the taskbar - same as "Win tab" -clutter
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "REG_DWORD" "0" "ShowTaskViewButton for %BASE%"

call :LOG Disable the people button in the taskbar
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" "PeopleBand" "REG_DWORD" "0" "PeopleBand for %BASE%"
 
call :LOG Enable right-click menu to auto end tasks from taskbar 
call :SetRegistryValueQuiet "%BASE%\Control Panel\Desktop" "AutoEndTasks" "REG_SZ" "1" "AutoEndTasks for %BASE%"

call :LOG Hide the meet now button on the taskbar
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "HideSCAMeetNow" "REG_DWORD" "1" "HideSCAMeetNow for %BASE%"

call :LOG Set the searchbox taskbar to icon only for less wasted space
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" "REG_DWORD" "1" "SearchboxTaskbarMode for %BASE%"

call :LOG Disabling Cross-Device Resume -optional but reverse this if you sync your phone to your pc - honestly your web browser should do this - mostly web
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" "IsResumeAllowed" "REG_DWORD" "0" "IsResumeAllowed for %BASE%"

call :LOG Disable MS Co-pilot per user registry settings -standard version - not m365 copilot
call :SetRegistryValueQuiet "%BASE%\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "REG_DWORD" "1" "TurnOffWindowsCopilot for %BASE%"
call :SetRegistryValueQuiet "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" "REG_DWORD" "0" "ShowCopilotButton for %BASE%"
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot" "AllowCopilotRuntime" "REG_DWORD" "0" "AllowCopilotRuntime for %BASE%"

call :LOG --- Disable Microsoft Office logging and telemetry
for %%V in (15.0 16.0) do (
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\%%V\Outlook\Options\Mail" "EnableLogging" "REG_DWORD" "0" "EnableLogging Office %%V for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\%%V\Outlook\Options\Calendar" "EnableCalendarLogging" "REG_DWORD" "0" "EnableCalendarLogging Office %%V for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\%%V\Word\Options" "EnableLogging" "REG_DWORD" "0" "EnableLogging Word %%V for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Policies\Microsoft\Office\%%V\OSM" "EnableLogging" "REG_DWORD" "0" "Enable Logging OSM %%V for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Policies\Microsoft\Office\%%V\OSM" "EnableUpload" "REG_DWORD" "0" "EnableUpload OSM %%V for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\%%V\Common" "QMEnable" "REG_DWORD" "0" "Office %%V QMEnable for %BASE%"
    call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\%%V\Common\Feedback" "Enabled" "REG_DWORD" "0" "Office %%V Feedback for %BASE%"
)
call :LOG --- Disable Microsoft Office client telemetry keys
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" "DisableTelemetry" "REG_DWORD" "1" "Disable Common Telemetry for %BASE%"
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" "DisableTelemetry" "REG_DWORD" "1" "Office 16 Client Telemetry for %BASE%"
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" "VerboseLogging" "REG_DWORD" "0" "Common ClientTelemetry for %BASE%"
call :SetRegistryValueQuiet "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" "VerboseLogging" "REG_DWORD" "0" "Office 16 VerboseLogging for %BASE%"

call :LOG Disabling sticky keys feature because leaving something on the shift key is just as bad as capslock for passwords
call :SetRegistryValueQuiet "%BASE%\Control Panel\Accessibility\StickyKeys" "Flags" "REG_SZ" "58" "StickyKeys hotkey disable for %BASE%"

::disabled this section because it negatively affects chips with CCD cache routing -X3d etc- and e-core parking when gaming
::add logic to detect if processor has CCD cache before disbling - for now leave as is
::disable game DVR
::call :SetRegistryValueQuiet "%BASE%\System\GameConfigStore" "GameDVR_Enabled" "REG_DWORD" "0" "GameDVR_Enabled for %BASE%"
::call :SetRegistryValueQuiet "%BASE%\System\GameConfigStore" "GameDVR_FSEBehavior" "REG_DWORD" "2" "GameDVR_FSEBehavior for %BASE%"
::call :SetRegistryValueQuiet "%BASE%\System\GameConfigStore" "GameDVR_FSEBehaviorMode" "REG_DWORD" "2" "GameDVR_FSEBehaviorMode for %BASE%"
::call :SetRegistryValueQuiet "%BASE%\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" "REG_DWORD" "0" "GameDVR_HonorUserFSEBehaviorMode for %BASE%"
::call :SetRegistryValueQuiet "%BASE%\System\GameConfigStore" "GameDVR_EFSEFeatureFlags" "REG_DWORD" "0" "GameDVR_EFSEFeatureFlags for %BASE%"

set "BASE="
exit /b 0

::********************************END of USER REGISTRY SETTINGS TO APPLY********************************
:IsProfileHiveLoaded
setlocal DisableDelayedExpansion
set "TBOK_PROFILE_CHECK=%~1"

if not defined TBOK_PROFILE_CHECK (
    endlocal
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $target = [IO.Path]::GetFullPath($env:TBOK_PROFILE_CHECK).TrimEnd([char]92);" ^
    "    $profile = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { $_.Loaded -and $_.LocalPath -and ([IO.Path]::GetFullPath($_.LocalPath).TrimEnd([char]92) -ieq $target) } | Select-Object -First 1;" ^
    "    if ($null -ne $profile) { exit 0 } else { exit 1 };" ^
    "} catch {" ^
    "    exit 2;" ^
    "}" >nul 2>&1

set "ProfileLoadedRC=%ERRORLEVEL%"
endlocal & exit /b %ProfileLoadedRC%

:UserRegistryDeployment
call :LOG Starting per-user registry deployment...

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :LOG Processing loaded user hives
set "LoadedUserHiveCount=0"

for /f "delims=" %%U in ('REG query HKEY_USERS 2^>nul ^| findstr /B /I /L /C:"HKEY_USERS\S-1-5-21-" /C:"HKEY_USERS\S-1-12-1-" ^| findstr /V /I /C:"_Classes"') do (
    set /a "LoadedUserHiveCount+=1"
    call :ApplySettings "%%U"
    set "LoadedUserSettingsRC=!ERRORLEVEL!"
        if not "!LoadedUserSettingsRC!"=="0" (
        call :LOG WARNING: ApplySettings did not complete for loaded hive %%U. Exit code: !LoadedUserSettingsRC!.
    )
)

if "!LoadedUserHiveCount!"=="0" (
    call :LOG NOTICE: No loaded user SID hives were found for registry deployment.
) else (
    call :LOG Loaded user hives processed: !LoadedUserHiveCount!.
)

set "LoadedUserHiveCount="
set "LoadedUserSettingsRC="
:: ================================
:: 2. ALL USER PROFILES
:: ================================
call :LOG Processing user profiles (NTUSER.DAT)

for /f "delims=" %%D in ('dir /b /ad "%SystemDrive%\Users" 2^>nul ^| findstr /V /I /X /C:"Public" /C:"Default" /C:"Default User" /C:"All Users"') do (
    set "PROFILE_NAME=%%D"
    set "PROFILE_PATH=%SystemDrive%\Users\%%D"
	
        if exist "!PROFILE_PATH!\NTUSER.DAT" (
            call :IsProfileHiveLoaded "!PROFILE_PATH!"
            set "ProfileAlreadyLoadedRC=!ERRORLEVEL!"

            if "!ProfileAlreadyLoadedRC!"=="0" (
                call :LOG Skipping offline processing for !PROFILE_PATH! because its registry hive is already loaded and was processed through HKEY_USERS.
            ) else (
                if "!ProfileAlreadyLoadedRC!"=="2" (
                    call :LOG WARNING: Loaded-profile detection failed for !PROFILE_PATH!. Offline processing will still be attempted.
                )

                if "!TBOK_RESTORE_POINT_FAILED!"=="1" (
                    if defined TBOK_PROFILE_BACKUP_DIR (
                        if exist "!TBOK_PROFILE_BACKUP_DIR!" (
                            copy /y "!PROFILE_PATH!\NTUSER.DAT" "!TBOK_PROFILE_BACKUP_DIR!\!PROFILE_NAME!-NTUSER.DAT" >>"%LOGFILE%" 2>&1
                            set "ProfileCopyRC=!ERRORLEVEL!"

                            if not "!ProfileCopyRC!"=="0" (
                                call :LOG NOTICE: A file-copy backup of NTUSER.DAT for !PROFILE_PATH! was not created.
                                call :LOG NOTICE: The hive may be loaded, locked, redirected, or otherwise unavailable to COPY.
                                call :LOG NOTICE: A registry-native backup will be attempted if the hive can be mounted.
                            ) else (
                                call :LOG Backed up NTUSER.DAT for !PROFILE_PATH!.
                            )
                        ) else (
                            call :LOG ERROR: The profile backup directory is unavailable for !PROFILE_PATH!.
                        )
                    ) else (
                        call :LOG ERROR: The profile backup directory is undefined for !PROFILE_PATH!.
                    )
                )

                call :LOG Loading hive for !PROFILE_PATH!

                REG query "HKU\TempHive" >nul 2>&1
                if not errorlevel 1 (
                    call :LOG WARNING: Found a previously mounted TempHive. Attempting cleanup.
                    REG unload "HKU\TempHive" >>"%LOGFILE%" 2>&1
                    set "TempHiveCleanupRC=!ERRORLEVEL!"

                    if not "!TempHiveCleanupRC!"=="0" (
                        call :LOG ERROR: Could not unload the previously mounted TempHive.
                    ) else (
                        call :LOG Temporary hive cleanup completed.
                    )
                )

                REG query "HKU\TempHive" >nul 2>&1
                if not errorlevel 1 (
                    call :LOG ERROR: TempHive remains mounted. Offline processing was skipped for !PROFILE_PATH!.
                ) else (
                    REG load "HKU\TempHive" "!PROFILE_PATH!\NTUSER.DAT" >>"%LOGFILE%" 2>&1
                    set "ProfileLoadRC=!ERRORLEVEL!"

                    if not "!ProfileLoadRC!"=="0" (
                        call :LOG Skipping offline load for !PROFILE_PATH!. The profile hive may already be loaded or currently in use.
                    ) else (
                        call :SaveMountedHiveBackup "HKU\TempHive" "!PROFILE_NAME!-NTUSER-SavedHive.dat" "!PROFILE_PATH!"
                        set "ProfileBackupRC=!ERRORLEVEL!"

                        if not "!ProfileBackupRC!"=="0" (
                            call :LOG WARNING: A registry-native hive backup could not be created for !PROFILE_PATH!.
                        )

                        call :ApplySettings "HKU\TempHive"
                        set "ProfileSettingsRC=!ERRORLEVEL!"

                        REG unload "HKU\TempHive" >>"%LOGFILE%" 2>&1
                        set "ProfileUnloadRC=!ERRORLEVEL!"

                        if not "!ProfileUnloadRC!"=="0" (
                            call :LOG ERROR: Failed to unload the temporary hive for !PROFILE_PATH!.
                        ) else if not "!ProfileSettingsRC!"=="0" (
                            call :LOG WARNING: The hive for !PROFILE_PATH! was unloaded, but one or more profile settings may have failed.
                        ) else (
                            call :LOG Successfully processed unloaded profile !PROFILE_PATH!.
                        )
                    )
                )
            )
        ) else (
            call :LOG Skipping profile directory without NTUSER.DAT: !PROFILE_PATH!
        )
)

set "PROFILE_NAME="
set "PROFILE_PATH="
set "ProfileAlreadyLoadedRC="
set "ProfileCopyRC="
set "TempHiveCleanupRC="
set "ProfileLoadRC="
set "ProfileBackupRC="
set "ProfileSettingsRC="
set "ProfileUnloadRC="

:: ================================
:: 3. DEFAULT PROFILE
:: ================================
call :LOG Processing Default profile...

if exist "%SystemDrive%\Users\Default\NTUSER.DAT" (
    if "!TBOK_RESTORE_POINT_FAILED!"=="1" (
        if defined TBOK_PROFILE_BACKUP_DIR (
            if exist "!TBOK_PROFILE_BACKUP_DIR!" (
                copy /y "%SystemDrive%\Users\Default\NTUSER.DAT" ^
                    "!TBOK_PROFILE_BACKUP_DIR!\Default-NTUSER.DAT" >>"%LOGFILE%" 2>&1

                if errorlevel 1 (
                    call :LOG NOTICE: A file-copy backup of the Default profile NTUSER.DAT was not created.
                    call :LOG NOTICE: A registry-native backup will be attempted after the hive is mounted.
                ) else (
                    call :LOG Backed up the Default profile NTUSER.DAT.
                )
            ) else (
                call :LOG WARNING: The profile backup directory is unavailable for the Default profile.
            )
        ) else (
            call :LOG WARNING: The profile backup directory is undefined for the Default profile.
        )
    )

    REG query "HKU\DefaultHive" >nul 2>&1

    if not errorlevel 1 (
        call :LOG WARNING: DefaultHive is already mounted. Attempting cleanup.
        REG unload "HKU\DefaultHive" >>"%LOGFILE%" 2>&1

        if errorlevel 1 (
            call :LOG ERROR: Could not unload the previously mounted DefaultHive.
        ) else (
            call :LOG Previous DefaultHive mount was unloaded successfully.
        )
    )

    REG load "HKU\DefaultHive" "%SystemDrive%\Users\Default\NTUSER.DAT" >>"%LOGFILE%" 2>&1
    set "DefaultHiveLoadRC=!ERRORLEVEL!"

    if not "!DefaultHiveLoadRC!"=="0" (
        call :LOG ERROR: Failed to load the Default profile. Exit code: !DefaultHiveLoadRC!.
    ) else (
        call :SaveMountedHiveBackup HKU\DefaultHive Default-NTUSER-SavedHive.dat "the Default profile"

        call :ApplySettings "HKU\DefaultHive"
        set "DefaultSettingsRC=!ERRORLEVEL!"

        REG unload "HKU\DefaultHive" >>"%LOGFILE%" 2>&1
        set "DefaultHiveUnloadRC=!ERRORLEVEL!"

        if not "!DefaultHiveUnloadRC!"=="0" (
            call :LOG ERROR: Failed to unload the Default profile. Exit code: !DefaultHiveUnloadRC!.
        ) else if not "!DefaultSettingsRC!"=="0" (
            call :LOG WARNING: The Default profile hive was unloaded, but one or more settings may have failed.
        ) else (
            call :LOG Default profile updated successfully.
        )
    )
) else (
    call :LOG WARNING: Default profile NTUSER.DAT was not found.
)

:: ===========================================
:: APPLY REGISTRY SETTINGS TO ALL USERS-END
:: ===========================================
call :LOG ===== SYSTEM AND USER OPTIMIZATIONS COMPLETE =====
call :LOG System and user optimization log: %LOGFILE%
exit /b 0
::======================================END FOR EACH USER REGISTRY LOOP==========================================

:GamingTweaks
if not defined CHASSISTYPE (
    call :GetChassisType
)

call :LOG ****************************************************************
call :LOG        Begin Gaming Improvements        
call :LOG **********************************************************
call :LOG 

call :RequireRollbackProtection "Gaming optimization changes"
if errorlevel 1 (
    call :LOG ERROR: Gaming optimizations were canceled because complete rollback protection could not be created.
    exit /b 1
)

call :LOG Resolving Current, Default, and LastKnownGood control-set mappings for gaming changes...
call :InitializeControlSetTargets
set "ControlSetMappingRC=!ERRORLEVEL!"

if not "!ControlSetMappingRC!"=="0" (
    call :LOG CRITICAL: Control-set role mappings could not be determined.
    call :LOG Gaming optimizations were stopped before control-set-specific changes were applied.
    exit /b 1
)

call :LOG Reset and Redetect Windows HPET dependency -High Precision Event Timer- - fixes issue where HPET was not detected properly
bcdedit.exe /deletevalue useplatformclock >nul 2>&1
if errorlevel 1 (
    call :LOG useplatformclock was not explicitly configured or could not be changed.
) else (
    call :LOG Removed explicit useplatformclock override.
)

call :LOG Requesting Hardware Accelerated GPU Scheduling (HAGS) where supported by the installed GPU and driver.
call :SetRegistryValue "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HWSchMode" "REG_DWORD" "2" "Hardware Accelerated GPU Scheduling mode"

call :LOG Enabling Optimizations for Windowed Games
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR\Graphics" "OptimizationsForWindowedGames" "REG_DWORD" "1" "OptimizationsForWindowedGames"

call :LOG Increasing system responsiveness for Games
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SystemResponsiveness" "REG_DWORD" "0x0000000a" "SystemResponsiveness"

call :LOG Applying Multimedia Class Scheduler Service tuning for Games and Audio workloads
::Games Multimedia Class Scheduler Service - GPU priority SFIO priority and Affinity are all listed as not yet used
::Scheduling priority High treats Task Priority setting as 2 instead of respecting number 1 low - 8 high
::call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" "REG_DWORD" "8" "GPU Priority 8 for Games"
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" "REG_DWORD" "6" "Priority"
call :SetRegistryValueQuiet "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" "REG_SZ" "Medium" "Scheduling Category"
::call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" "REG_SZ "High" "SFIO High Priority for Games"
::The Latency Sensitive value is defaulted to TRUE - this key is here to ensure defaults
call :SetRegistryValueQuiet "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Latency Sensitive" "REG_SZ" "True" "Latency Sensitive"

::Audio Multimedia Class Scheduler Service
::call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" "GPU Priority" "REG_DWORD" "8" "GPU Priority 8 for Audio"
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" "Priority" "REG_DWORD" "6" "Priority"
call :SetRegistryValueQuiet "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" "Scheduling Category" "REG_SZ" "Medium" "Scheduling Category"
::call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" "SFIO Priority" "REG_SZ" "High" "SFIO High Priority for audio"
::The Latency Sensitive value is defaulted to TRUE - this key is here to ensure defaults
call :SetRegistryValueQuiet "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" "Latency Sensitive" "REG_SZ" "True" "Latency Sensitive"

:detectchassisGamingTweaks
call :LOG Detected chassis category: !CHASSISTYPE!

if /i "!CHASSISTYPE!"=="Laptop" goto laptopgaming
if /i "!CHASSISTYPE!"=="Desktop" goto desktopgaming
goto unknownchassisgaming

:laptopgaming
call :LOG Laptop detected - desktop-only power tweaks were skipped.

call :LOG Unlocking all hidden Power Plan attributes

set "TBOK_POWER_UNLOCK=%TEMP%\TBOK-PowerUnlock-%RANDOM%-%RANDOM%.ps1"

(
echo $keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings' -Recurse -ErrorAction SilentlyContinue
echo foreach ^($key in $keys^) ^{
echo     try ^{
echo         if ^($key.Name -notmatch 'DefaultPowerSchemeValues'^) ^{
echo             Set-ItemProperty -Path $key.PSPath -Name Attributes -Value 2 -Force -ErrorAction SilentlyContinue
echo         ^}
echo     ^}
echo     catch ^{
echo     ^}
echo ^}
) > "!TBOK_POWER_UNLOCK!"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "!TBOK_POWER_UNLOCK!" >>"%LOGFILE%" 2>&1

set "PowerUnlockRC=!ERRORLEVEL!"

if exist "!TBOK_POWER_UNLOCK!" (
    del /q "!TBOK_POWER_UNLOCK!" >nul 2>&1
)

if not "!PowerUnlockRC!"=="0" (
    call :LOG WARNING: Failed to unlock one or more hidden power settings. Exit code: !PowerUnlockRC!.
) else (
    call :LOG Hidden power-plan settings unlocked successfully.
)


Call :LOG Activating Processor Performance Boost Mode 3 for Efficient Agressive
powercfg -attributes sub_processor perfboostmode -attrib_hide
powercfg -q scheme_current sub_processor perfboostmode
powercfg -s scheme_current
powercfg -setdcvalueindex scheme_current sub_processor perfboostmode 3
powercfg -s scheme_current

goto :GamingTweaksComplete

:desktopgaming
call :LOG Desktop detected - enabling desktop-only optimizations
call :LOG Disabling PowerThrottling
call :SetAllControlSetValues "Control\Power\PowerThrottling" "PowerThrottlingOff" "REG_DWORD" "1" "PowerThrottlingOff"

:: Community-derived setting; not currently documented by Microsoft
::Windows has a lazy mode mechanism in the MMCS CPU power management subsystem that allows the system 
::to skip or defer some hardware events when CPU usage is low. This can save power but also introduces
:: a small delay before the CPU reacts to input or events
::The NoLazyMode key overrides this behavior by telling the system not to skip events, so the CPU processes them as soon as they occur
call :LOG  Disabling LazyMode CPU scheduling
call :SetAllControlSetValues "Control\Power\PowerThrottling" "NoLazyMode" "REG_DWORD" "1" "Power throttling NoLazyMode"

:: Community-derived setting; not currently documented by Microsoft.
call :LOG Setting the undocumented AlwaysOn power-throttling value to 0.
call :SetAllControlSetValues "Control\Power\PowerThrottling" "AlwaysOn" "REG_DWORD" "0" "Power throttling AlwaysOn"

call :LOG Enabling Ultimate Performance power plan for physical desktops only
set "ULTIMATE_GUID="

for /f "tokens=4" %%G in ('powercfg.exe /list 2^>nul ^| findstr /I /C:"Ultimate Performance"') do (
    if not defined ULTIMATE_GUID set "ULTIMATE_GUID=%%G"
)

if defined ULTIMATE_GUID (
    call :LOG Existing Ultimate Performance plan found: !ULTIMATE_GUID!
) else (
    call :LOG Ultimate Performance plan was not found. Creating it...
    for /f "tokens=4" %%G in ('powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2^>nul') do (
        if not defined ULTIMATE_GUID set "ULTIMATE_GUID=%%G"
    )
)

if not defined ULTIMATE_GUID (
    call :LOG WARNING: Could not find or create the Ultimate Performance power plan.
) else (
    powercfg.exe /setactive !ULTIMATE_GUID! >>"%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :LOG ERROR: Failed to activate Ultimate Performance plan !ULTIMATE_GUID!.
    ) else (
        call :LOG Ultimate Performance plan activated: !ULTIMATE_GUID!
    )
)
Call :LOG Activating Processor Performance Boost Mode 2 for Aggressive at Guaranteed
powercfg -attributes sub_processor perfboostmode -attrib_hide
powercfg -q scheme_current sub_processor perfboostmode
powercfg -s scheme_current
powercfg -setdcvalueindex scheme_current sub_processor perfboostmode 2
powercfg -s scheme_current

call :LOG Unlocking all hidden Power Plan attributes

set "TBOK_POWER_UNLOCK=%TEMP%\TBOK-PowerUnlock-%RANDOM%-%RANDOM%.ps1"

(
echo $keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings' -Recurse -ErrorAction SilentlyContinue
echo foreach ^($key in $keys^) ^{
echo     try ^{
echo         if ^($key.Name -notmatch 'DefaultPowerSchemeValues'^) ^{
echo             Set-ItemProperty -Path $key.PSPath -Name Attributes -Value 2 -Force -ErrorAction SilentlyContinue
echo         ^}
echo     ^}
echo     catch ^{
echo     ^}
echo ^}
) > "!TBOK_POWER_UNLOCK!"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "!TBOK_POWER_UNLOCK!" >>"%LOGFILE%" 2>&1

set "PowerUnlockRC=!ERRORLEVEL!"

if exist "!TBOK_POWER_UNLOCK!" (
    del /q "!TBOK_POWER_UNLOCK!" >nul 2>&1
)

if not "!PowerUnlockRC!"=="0" (
    call :LOG WARNING: Failed to unlock one or more hidden power settings. Exit code: !PowerUnlockRC!.
) else (
    call :LOG Hidden power-plan settings unlocked successfully.
)

set "ULTIMATE_GUID="

goto :GamingTweaksComplete

:unknownchassisgaming
call :LOG Unable to determine chassis type. Desktop-only power tweaks were skipped.
goto :GamingTweaksComplete

:GamingTweaksComplete
call :LOG ****************************************************************
call :LOG Completed Gaming Improvements
call :LOG ****************************************************************
call :LOG
exit /b 0

:WinGet
call :LOG CAUTION - WINGET DOES NOT CONTROL PACKAGES WITH REBOOT AUTO ENABLED
call :LOG CAUTION - RUNNING THIS ON A REMOTE MACHINE COULD REBOOT THE PC AS PART OF THE SOFTWARE UPDATE PROCESS
call :LOG CAUTION - IT IS DEFAULTED TO NOT REBOOT BUT SOME PACKAGES IGNORE THE REQUEST
call :LOG CAUTION - MICROSOFT IS "WORKING TO RESOLVE THIS WITH 3RD PARTY PACKAGE MANAGERS"
ECHO.
call :LOG Installing or updating the WinGet Package Manager prerequisites

powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop" >>"%LOGFILE%" 2>&1
set "WinGetProviderRC=!ERRORLEVEL!"
if not "!WinGetProviderRC!"=="0" (
    call :LOG ERROR: NuGet package-provider installation or verification failed. Exit code: !WinGetProviderRC!.
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Install-Module -Name Microsoft.WinGet.Client -Force -ErrorAction Stop" >>"%LOGFILE%" 2>&1
set "WinGetModuleRC=!ERRORLEVEL!"
if not "!WinGetModuleRC!"=="0" (
    call :LOG ERROR: Microsoft.WinGet.Client installation or update failed. Exit code: !WinGetModuleRC!.
    exit /b 1
)

call :LOG Searching for and updating existing installed packages

winget.exe update --all --include-unknown --accept-source-agreements --accept-package-agreements --silent --verbose >>"%LOGFILE%" 2>&1
set "WinGetUpdateRC=!ERRORLEVEL!"
if not "!WinGetUpdateRC!"=="0" (
    call :LOG WARNING: WinGet completed with exit code !WinGetUpdateRC!.
    exit /b 1
)

call :LOG WinGet application updates completed successfully.
exit /b 0

:BeardSweeper
call :LOG BeardSweeper integration is currently in development - only safe non-destructive options have been added.
call :LOG Configuring and Running Enhanced DiskCleanup routine
:CLEANMGR
	ECHO Maximizing Disk Cleanup registry settings for all safe to delete content

:: Set all the CLEANMGR registry entries for Group #69 -have a sense of humor!
	SET "_Group_No=StateFlags0069"	
	SET "_RootKey=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

:: Temporary Setup Files
	REG ADD "%_RootKey%\Active Setup Temp Folders" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Branch Cache (WAN bandwidth optimization)
	REG ADD "%_RootKey%\BranchCache" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Catalog Files for the Content Indexer (deletes all files in the folder c:\catalog.wci)
	REG ADD "%_RootKey%\Content Indexer Cleaner" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Delivery Optimization Files (service to share bandwidth for uploading Windows updates)
	REG ADD "%_RootKey%\Delivery Optimization Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Diagnostic data viewer database files (Windows app that sends data to Microsoft)
	REG ADD "%_RootKey%\Diagnostic Data Viewer database Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Direct X Shader cache (graphics cache, clearing this can can speed up application load time.)
	REG ADD "%_RootKey%\D3D Shader Cache" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Downloaded Program Files (ActiveX controls and Java applets downloaded from the Internet)
	REG ADD "%_RootKey%\Downloaded Program Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Temporary Internet Files
	REG ADD "%_RootKey%\Internet Cache Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Language resources Files (unused languages and keyboard layouts)
	REG ADD "%_RootKey%\Language Pack" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Offline Files (Web pages)
	REG ADD "%_RootKey%\Offline Pages Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Old ChkDsk Files
	REG ADD "%_RootKey%\Old ChkDsk Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Recycle Bin -If you store stuff in recycle bin... shame on you!
	REG ADD "%_RootKey%\Recycle Bin" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Retail Demo
	REG ADD "%_RootKey%\RetailDemo Offline Content" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Update package Backup Files (old versions)
	REG ADD "%_RootKey%\ServicePack Cleanup" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Setup Log files (software install logs)
	REG ADD "%_RootKey%\Setup Log Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: System Error memory dump files (These can be very large if the system has crashed)
	REG ADD "%_RootKey%\System error memory dump files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: System Error minidump files (smaller memory crash dumps)
	REG ADD "%_RootKey%\System error minidump files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Temporary Files (%Windir%\Temp and %Windir%\Logs)
	REG ADD "%_RootKey%\Temporary Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Windows Update Cleanup (old system files not migrated during a Windows Upgrade)
	REG ADD "%_RootKey%\Update Cleanup" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Thumbnails (Explorer will recreate thumbnails as each folder is viewed.)
	REG ADD "%_RootKey%\Thumbnail Cache" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1

:: Windows Defender Antivirus
	REG ADD "%_RootKey%\Windows Defender" /v %_Group_No% /d 2 /t REG_DWORD /f	>nul 2>&1

:: Windows error reports and feedback diagnostics
	REG ADD "%_RootKey%\Windows Error Reporting Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f 	>nul 2>&1

:: Windows Upgrade log files
	REG ADD "%_RootKey%\Windows Upgrade Log Files" /v %_Group_No% /t REG_DWORD /d 00000002 /f	>nul 2>&1
call :LOG Disk Cleanup registry settings completed.
call :LOG Running Windows Disk Cleanup. This can take a while.

start "" /wait cleanmgr.exe /sagerun:69 >>"%LOGFILE%" 2>&1
set "CleanMgrRC=!ERRORLEVEL!"

if not "!CleanMgrRC!"=="0" (
    call :LOG WARNING: Disk Cleanup returned exit code !CleanMgrRC!.
) else (
    call :LOG Disk Cleanup completed successfully.
)

call :LOG Cleaning superseded Windows component-store versions.

DISM.exe /Online /Cleanup-Image /StartComponentCleanup >>"%LOGFILE%" 2>&1
set "ComponentCleanupRC=!ERRORLEVEL!"

if not "!ComponentCleanupRC!"=="0" (
    call :LOG WARNING: Component-store cleanup returned exit code !ComponentCleanupRC!.
) else (
    call :LOG Component-store cleanup completed successfully.
)

set "_Group_No="
set "_RootKey="

if not "!CleanMgrRC!"=="0" exit /b 1
if not "!ComponentCleanupRC!"=="0" exit /b 1

call :LOG BeardSweeper cleanup completed successfully.
exit /b 0
exit /b 0

:Finished
call :LOG ****************************ALL FINISHED!******************************
call :LOG .
call :LOG .    IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE
call :LOG .         "https://buymeacoffee.com/thebeardofl"
call :LOG .
call :LOG ****************************ALL FINISHED!******************************

if defined TBOK_NONINTERACTIVE (
    if defined TBOK_RUN_RESTART (
        call :LOG Noninteractive execution completed.
        call :LOG /RESTART specified. The computer will now restart.
        goto :RESTART
    )
    call :LOG Noninteractive execution detected. The computer will not restart automatically.
    call :LOG Restart the computer manually when appropriate.
    goto :EXIT
)

choice.exe /c RME /n /m "Restart now, Menu, or Exit? [R/M/E]: Default E in 15 seconds " /t 15 /d E 2>>"%LOGFILE%"
set "RestartChoiceRC=%ERRORLEVEL%"

if "%RestartChoiceRC%"=="255" (
    call :LOG NOTICE: Interactive console input is unavailable.
    call :LOG The script will exit without restarting the computer.
    goto :EXIT
)

if "%RestartChoiceRC%"=="3" (
    call :LOG Exit selected. The computer will not restart automatically.
    goto :EXIT
)

if "%RestartChoiceRC%"=="2" (
    call :LOG Returning to the main menu without restarting.
    set "TBOK_NONINTERACTIVE="
    goto :MENU
)

if "%RestartChoiceRC%"=="1" (
    goto :RESTART
)

call :LOG WARNING: Unexpected restart prompt return code: %RestartChoiceRC%.
call :LOG The script will exit without restarting the computer.
goto :EXIT

:RESTART
call :LOG Restarting PC.
call :CleanupTemporaryPlans
endlocal
shutdown.exe /r /t 0
exit /b 0

:EXIT
call :LOG Script exiting.
call :CleanupTemporaryPlans
endlocal
call :Delay 10
exit /b 0
