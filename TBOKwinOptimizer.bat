:: Requirements - Windows 10 or Windows 11 with Windows PowerShell 5.1
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
:: FYI you can now run this script on remote computer using the following switches for a menuless run:
::   /optimize - runs the main routine to optimize and debloat 
::   /cleanup - Agressive disk cleanup using my BeardSweeper script
::   /gaming - apply gaming tweaks 
::   /winget - full auto software update using WinGet
::   /newlog - starts a new log file for the workstation being run on, if not it will reuse existing
::   /restart - restarts the computer after all requested noninteractive operations complete
::   /remote COMPUTERNAME - copies TBOK to the remote workstation and executes the requested
::    noninteractive operations there, retrieves logs to the local script directory,
::    and processes /RESTART only after artifact retrieval completes
::   /remotelist FILE - sequentially runs the requested operations on each
:: computer listed in FILE. One computer name per line. Blank lines and
:: lines beginning with # are ignored.
:: Example:
:: TBOKwinOptimizer-Vx-x-x.bat /OPTIMIZE /CLEANUP /RESTART /REMOTELIST computers.txt
::   Requirements for /remote and /Remotelist: 
::   The destination must accept WS-Management remoting connections
::   The source computer account must have administrative rights on the remote computer


::turn off echoing all commands
@ECHO OFF
::Relaunch under the native 64-bit cmd.exe when started from a 32-bit host (many RMM
::agents and deployment tools are 32-bit). Under WOW64, System32 is redirected to
::SysWOW64 and HKLM\SOFTWARE writes are redirected to WOW6432Node, so settings would be
::reported as applied while landing where 64-bit Windows never reads them.
::exit /b without a number keeps the 64-bit run's exit code.
if defined PROCESSOR_ARCHITEW6432 if exist "%SystemRoot%\Sysnative\cmd.exe" (
    "%SystemRoot%\Sysnative\cmd.exe" /d /c ""%~f0" %*"
    exit /b
)
::change the terminal color to something friendlier
color f0

::enable holding variables during script,explicitely enable command extensions, disable variable expansions
setlocal EnableExtensions DisableDelayedExpansion

::Security: never resolve bare command names from the current directory.
::cmd searches the current directory before PATH. This script calls powershell.exe, REG,
::findstr, sc, net, choice and others by bare name, and its working directory is normally
::the folder it was launched from (Downloads, a deployment share, or the remote staging
::folder). Any executable or .bat/.cmd placed there under one of those names would run with
::this script's administrative rights. Disable current-directory lookup and work from
::System32. The script locates its own files through %~dp0, so nothing else changes.
::TBOK_START_DIR keeps the launch directory for resolving relative /REMOTELIST paths.
::The directory change is scoped by the SETLOCAL above and is undone when the script ends.
set "NoDefaultCurrentDirectoryInExePath=1"
set "TBOK_START_DIR=%CD%"
cd /d "%SystemRoot%\System32"

::add ANSI color support
for /f %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"
::resets color to black background white text
set "CLR_RESET=%ESC%[30;107m"

set "CLR_TITLE=%ESC%[34m"
::Black
set "CLR_MENU=%ESC%[30m"
::Blue
set "CLR_OPTION=%ESC%[34m"
::Green
set "CLR_INFO=%ESC%[32m"
::Red
set "CLR_WARN=%ESC%[31m"
::Purple
set "CLR_STATUS=%ESC%[35m"

::individual colors
set "CLR_RED=%ESC%[91m"
set "CLR_GREEN=%ESC%[92m"
set "CLR_YELLOW=%ESC%[93m"
set "CLR_BLUE=%ESC%[94m"
set "CLR_CYAN=%ESC%[96m"
set "CLR_WHITE=%ESC%[97m"


::Script release version and release date 
:ScriptVersion
set "VERSION=1.7.1"
set "VERDATE=10-28-2026"

:Elevation
:: Automatically check for and obtain administrative elevation, retain working directory, allow special characters in path names
cls
echo Checking for Admin permissions using fltmc, No changes are being made at this time.

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not errorlevel 1 goto :GotPrivileges

::verify that powershell has not been removed
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    echo.
    echo ERROR: Windows PowerShell is unavailable.
    echo TBOK requires Windows PowerShell 5.1 or later.
    echo.
    pause
    exit /b 1
)

echo Requesting administrative elevation...

set "ELEVATE_SCRIPT=%~f0"
set "ELEVATE_WORKDIR=%~dp0"
set "ELEVATE_ARGUMENTS=%*"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Command ^
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

call :CheckPowerShellRequirements

if errorlevel 1 (
    echo.
    echo ERROR: TBOK requires Windows PowerShell 5.1 or later.
    echo ERROR: One or more required Windows PowerShell capabilities are unavailable.
    echo.
    pause
    exit /b 1
)
ECHO Analyzing System to create optimized plan, please wait...
call :ShowAnalysisProgress 0 "Starting system analysis"

:BEGIN-SCRIPT-HELPERS
::These are items that are called later in the script to perform a function - trims the code size for repeat items
::enable extended script logic and delayed expansion
setlocal EnableExtensions EnableDelayedExpansion

call :DetectRemoteRequest %*
set "RemoteDetectionRC=!ERRORLEVEL!"
if not "!RemoteDetectionRC!"=="0" (
    echo ERROR: The remote-execution request is invalid.
    exit /b !RemoteDetectionRC!
)

if defined TBOK_REMOTE_LIST_FILE (
    call :RunRemoteList
    set "RemoteExecutionRC=!ERRORLEVEL!"
    exit /b !RemoteExecutionRC!
)

if defined TBOK_REMOTE_HOST (
    call :RunRemoteController
    set "RemoteExecutionRC=!ERRORLEVEL!"
    exit /b !RemoteExecutionRC!
)

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
set "TBOK_NEWLOG_REQUESTED=0"

for %%A in (%*) do (
    if /I "%%~A"=="/NEWLOG" (
        set "TBOK_NEWLOG_REQUESTED=1"
    )
)
set "TBOK_LOG_WAS_CREATED=0"
set "LOGFILE="

:: User explicitly requested a fresh logfile.
if "!TBOK_NEWLOG_REQUESTED!"=="0" (
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
:: Echoes to the console and logfile.
:: During analysis-progress mode, normal messages are logged but not echoed.
:: During profile-summary mode, routine messages are suppressed while
:: ERROR and WARNING messages remain visible.
:: Security: the message is captured with delayed expansion disabled and printed with
:: delayed expansion enabled. Delayed expansion inserts the text after cmd has parsed
:: the line, so & | < > ^ inside a message are printed, never executed.
setlocal DisableDelayedExpansion

set "LogMessage=%*"
set "LogMessageType=%LogMessage:~0,8%"

if defined TBOK_PROFILE_SUMMARY_MODE (
    if /I not "%LogMessage:~0,6%"=="ERROR:" (
        if /I not "%LogMessageType%"=="WARNING:" (
            endlocal
            exit /b 0
        )
    )
)
setlocal EnableDelayedExpansion
if not defined TBOK_ANALYSIS_PROGRESS_ACTIVE echo(!LogMessage!
>>"!LOGFILE!" echo([!DATE! !TIME!] !LogMessage!
endlocal
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

:ShowAnalysisProgress
setlocal DisableDelayedExpansion

set "ProgressPercent=%~1"
set "ProgressText=%~2"
set "ProgressBar="

if not defined ProgressPercent set "ProgressPercent=0"

if %ProgressPercent% GEQ 10 set "ProgressBar=#"
if %ProgressPercent% GEQ 20 set "ProgressBar=##"
if %ProgressPercent% GEQ 30 set "ProgressBar=###"
if %ProgressPercent% GEQ 40 set "ProgressBar=####"
if %ProgressPercent% GEQ 50 set "ProgressBar=#####"
if %ProgressPercent% GEQ 60 set "ProgressBar=######"
if %ProgressPercent% GEQ 70 set "ProgressBar=#######"
if %ProgressPercent% GEQ 80 set "ProgressBar=########"
if %ProgressPercent% GEQ 90 set "ProgressBar=#########"
if %ProgressPercent% GEQ 100 set "ProgressBar=##########"

set "ProgressBar=%ProgressBar%----------"
set "ProgressBar=%ProgressBar:~0,10%"

<nul set /p "=%ESC%[2K%ESC%[1G%CLR_STATUS%[%ProgressBar%] %ProgressPercent%%%  %ProgressText%%CLR_RESET%"

if %ProgressPercent% GEQ 100 echo(

endlocal
exit /b 0

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

:CheckPowerShellRequirements
setlocal DisableDelayedExpansion

powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop';$v=$PSVersionTable.PSVersion;if($v -lt [version]'5.1'){exit 11};$edition=$PSVersionTable.PSEdition;if($edition -and $edition -ne 'Desktop'){exit 12};$required=@('Get-CimInstance','Invoke-CimMethod','New-PSSession','Invoke-Command','Copy-Item','Start-Process','Get-Process','Wait-Process');foreach($name in $required){if(-not(Get-Command $name -ErrorAction SilentlyContinue)){Write-Output ('MISSING: '+$name);exit 13}};Write-Output ('Windows PowerShell '+$v.ToString()+' requirement check passed.');exit 0"

set "PowerShellRequirementRC=%ERRORLEVEL%"

if not "%PowerShellRequirementRC%"=="0" (
    endlocal
    exit /b %PowerShellRequirementRC%
)

endlocal
exit /b 0

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
    REM Security: this folder receives full exports of HKLM and every user hive, plus
    REM NTUSER.DAT copies. Restrict it to SYSTEM and Administrators instead of inheriting
    REM the permissions of the folder the script was launched from.
    icacls "!TBOK_PROFILE_BACKUP_DIR!" /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" >>"%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :LOG WARNING: Could not restrict permissions on the fallback backup directory.
    )
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
:: Return codes:
:: 0 = Rollback protection is usable.
:: 1 = Complete rollback protection could not be created.
set "ProtectedOperation=%~1"
set "RollbackRC="
set "RollbackResult=1"

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
set "TBOK_EXISTING_BACKUP_DIR="

for /f "delims=" %%A in (
    'powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd"'
) do (
    set "TBOK_TODAY=%%A"
)

if defined TBOK_TODAY (
    for /d %%D in ("%~dp0TBOK-RegistryBackups-%COMPUTERNAME%-!TBOK_TODAY!-*") do (
        if exist "%%~fD\HKLM-Before-TBOK.reg" (
            if exist "%%~fD\HKCU-ExecutionAccount-Before-TBOK.reg" (
                set "TBOK_BACKUPS_ALREADY_EXIST=1"
                set "TBOK_EXISTING_BACKUP_DIR=%%~fD"
            )
        )
    )
)

if "!TBOK_BACKUPS_ALREADY_EXIST!"=="1" (
    call :LOG Complete rollback backup files from today were found.
    call :LOG Backup directory: !TBOK_EXISTING_BACKUP_DIR!
    call :LOG Skipping duplicate restore-point and registry-export generation.
    set "TBOK_PROFILE_BACKUP_DIR=!TBOK_EXISTING_BACKUP_DIR!"
    set "TBOK_RESTORE_POINT_FAILED=1"
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    set "RollbackResult=0"
    goto :RequireRollbackProtectionComplete
)

set "TBOK_BACKUPS_ALREADY_EXIST="
set "TBOK_TODAY="
set "TBOK_EXISTING_BACKUP_DIR="

call :PrepareRollbackProtection
set "RollbackRC=!ERRORLEVEL!"

if "!RollbackRC!"=="0" (
    call :LOG Restore-point rollback protection was created successfully.
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    set "RollbackResult=0"
    goto :RequireRollbackProtectionComplete
)

if "!RollbackRC!"=="1" (
    call :LOG NOTICE: The restore point failed, but complete fallback registry exports were created.
    set "TBOK_ROLLBACK_ALREADY_VERIFIED=1"
    set "RollbackResult=0"
    goto :RequireRollbackProtectionComplete
)

call :LOG CRITICAL: Complete rollback protection could not be created.
call :LOG CRITICAL: !ProtectedOperation! will not be applied.
set "RollbackResult=1"

:RequireRollbackProtectionComplete
set "ProtectedOperation="
set "RollbackRC="
set "TBOK_BACKUPS_ALREADY_EXIST="
set "TBOK_TODAY="
set "TBOK_EXISTING_BACKUP_DIR="

exit /b !RollbackResult!

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
set "TBOK_STARTMODE_VALID=0"

if not defined TBOK_SERVICE (
    endlocal
    call :LOG ERROR: SetServiceStartup called without a service name.
    exit /b 2
)
if /I "%TBOK_STARTMODE%"=="auto" (
    set "TBOK_STARTMODE_VALID=1"
)
if /I "%TBOK_STARTMODE%"=="delayed-auto" (
    set "TBOK_STARTMODE_VALID=1"
)
if /I "%TBOK_STARTMODE%"=="demand" (
    set "TBOK_STARTMODE_VALID=1"
)
if /I "%TBOK_STARTMODE%"=="disabled" (
    set "TBOK_STARTMODE_VALID=1"
)
if "%TBOK_STARTMODE_VALID%"=="0" (
    endlocal
    call :LOG ERROR: Invalid startup mode "%~2" for service "%~1".
    exit /b 2
)
if not defined TBOK_SERVICE_PLAN (
    endlocal
    call :LOG ERROR: Service startup plan file has not been initialized.
    exit /b 3
)

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
:: Queries and configures one named registry value.
:: Outside profile-summary mode: Logs MATCH, CREATE, CHANGE, or ERROR.
:: During profile-summary mode: Increments Applied, Skipped, or Failed counters.
setlocal EnableExtensions EnableDelayedExpansion

set "RegPath=%~1"
set "RegName=%~2"
set "RegType=%~3"
set "RegData=%~4"
set "RegDescription=%~5"
set "CurrentType="
set "CurrentData="
set "OriginalType="
set "OriginalData="
set "RegistryWriteRC="

if not defined RegPath goto :SetRegistryValue_InvalidPath
if not defined RegName goto :SetRegistryValue_InvalidName
if not defined RegType goto :SetRegistryValue_InvalidType

if not defined RegDescription set "RegDescription=!RegName!"

for /f "skip=2 tokens=1,2,*" %%A in ('REG QUERY "!RegPath!" /v "!RegName!" 2^>nul') do (
    set "CurrentType=%%B"
    set "CurrentData=%%C"
)

if not defined CurrentType goto :SetRegistryValue_Create

if /I "!CurrentType!"=="!RegType!" (
    if /I "!CurrentData!"=="!RegData!" (
        goto :SetRegistryValue_Match
    )
)

set "OriginalType=!CurrentType!"
set "OriginalData=!CurrentData!"
goto :SetRegistryValue_WriteChange


:SetRegistryValue_Create
REG ADD "!RegPath!" /v "!RegName!" /t "!RegType!" /d "!RegData!" /f >>"%LOGFILE%" 2>&1
set "RegistryWriteRC=!ERRORLEVEL!"

if not "!RegistryWriteRC!"=="0" goto :SetRegistryValue_Failed
goto :SetRegistryValue_Created


:SetRegistryValue_WriteChange
REG ADD "!RegPath!" /v "!RegName!" /t "!RegType!" /d "!RegData!" /f >>"%LOGFILE%" 2>&1
set "RegistryWriteRC=!ERRORLEVEL!"

if not "!RegistryWriteRC!"=="0" goto :SetRegistryValue_Failed
goto :SetRegistryValue_Changed


:SetRegistryValue_Match
if defined TBOK_PROFILE_SUMMARY_MODE goto :SetRegistryValue_SummarySkipped

call :LOG MATCH: !RegDescription! already equals !RegData! [!RegType!]. No changes were made.
endlocal
exit /b 0


:SetRegistryValue_Created
if defined TBOK_PROFILE_SUMMARY_MODE goto :SetRegistryValue_SummaryApplied

call :LOG CREATE: !RegDescription! was not present; created as !RegData! [!RegType!].
endlocal
exit /b 0


:SetRegistryValue_Changed
if defined TBOK_PROFILE_SUMMARY_MODE goto :SetRegistryValue_SummaryApplied

call :LOG CHANGE: !RegDescription! original value: !OriginalData! [!OriginalType!]; changed to: !RegData! [!RegType!].
endlocal
exit /b 0


:SetRegistryValue_Failed
if defined TBOK_PROFILE_SUMMARY_MODE goto :SetRegistryValue_SummaryFailed

call :LOG ERROR: Failed to configure !RegDescription!. Exit code: !RegistryWriteRC!.
endlocal
exit /b 1


:SetRegistryValue_SummarySkipped
endlocal
set /a "TBOK_PROFILE_SKIPPED+=1" >nul 2>&1
exit /b 0


:SetRegistryValue_SummaryApplied
endlocal
set /a "TBOK_PROFILE_APPLIED+=1" >nul 2>&1
exit /b 0


:SetRegistryValue_SummaryFailed
call :LOG ERROR: Failed to configure !RegDescription!. Exit code: !RegistryWriteRC!.
endlocal
set /a "TBOK_PROFILE_FAILED+=1" >nul 2>&1
exit /b 1


:SetRegistryValue_InvalidPath
call :LOG ERROR: SetRegistryValue was called without a registry path.
endlocal
exit /b 2


:SetRegistryValue_InvalidName
call :LOG ERROR: SetRegistryValue was called without a registry value name.
endlocal
exit /b 2


:SetRegistryValue_InvalidType
call :LOG ERROR: SetRegistryValue was called without a registry type.
endlocal
exit /b 2

:SetRegistryValueQuiet
:: Adds a named registry value without querying its previous state.
:: In profile-summary mode, successful writes count as Applied.
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
    for %%R in ("%RegWriteRC%") do (
        if defined TBOK_PROFILE_SUMMARY_MODE (
            endlocal & set /a "TBOK_PROFILE_FAILED+=1" >nul 2>&1
            call :LOG ERROR: Failed to configure %~5. Exit code: %%~R.
        ) else (
            endlocal
            call :LOG ERROR: Failed to configure %~5. Exit code: %%~R.
        )
        exit /b 1
    )
)
if defined TBOK_PROFILE_SUMMARY_MODE (
    endlocal & set /a "TBOK_PROFILE_APPLIED+=1" >nul 2>&1
) else (
    endlocal
)
exit /b 0

:EnsureRegistryKey
:: Creates or verifies a registry key.
setlocal DisableDelayedExpansion
if "%~1"=="" (
    endlocal
    call :LOG ERROR: EnsureRegistryKey was called without a registry path.
    exit /b 2
)
REG ADD "%~1" /f >nul 2>>"%LOGFILE%"
set "RegistryKeyRC=%ERRORLEVEL%"

if not "%RegistryKeyRC%"=="0" (
    for %%R in ("%RegistryKeyRC%") do (
        if defined TBOK_PROFILE_SUMMARY_MODE (
            endlocal & set /a "TBOK_PROFILE_FAILED+=1" >nul 2>&1
            call :LOG ERROR: Failed to create or verify %~2. Exit code: %%~R.
        ) else (
            endlocal
            call :LOG ERROR: Failed to create or verify %~2. Exit code: %%~R.
        )
        exit /b 1
    )
)
if defined TBOK_PROFILE_SUMMARY_MODE (
    endlocal & set /a "TBOK_PROFILE_APPLIED+=1" >nul 2>&1
) else (
    endlocal
)
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
    if defined TBOK_PROFILE_SUMMARY_MODE (
        endlocal & set /a "TBOK_PROFILE_SKIPPED+=1" >nul 2>&1
    ) else (
        endlocal
    )
    exit /b 0
)
REG delete "%~1" /f >nul 2>>"%LOGFILE%"
set "DeleteKeyRC=%ERRORLEVEL%"
if not "%DeleteKeyRC%"=="0" (
    for %%R in ("%DeleteKeyRC%") do (
        if defined TBOK_PROFILE_SUMMARY_MODE (
            endlocal & set /a "TBOK_PROFILE_FAILED+=1" >nul 2>&1
            call :LOG ERROR: Failed to delete %~2. Exit code: %%~R.
        ) else (
            endlocal
            call :LOG ERROR: Failed to delete %~2. Exit code: %%~R.
        )
        exit /b 1
    )
)
if defined TBOK_PROFILE_SUMMARY_MODE (
    endlocal & set /a "TBOK_PROFILE_APPLIED+=1" >nul 2>&1
) else (
    endlocal
    call :LOG Deleted %~2.
)
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
    if defined TBOK_PROFILE_SUMMARY_MODE (
        endlocal & set /a "TBOK_PROFILE_SKIPPED+=1" >nul 2>&1
    ) else (
        endlocal
    )
    exit /b 0
)
REG delete "%~1" /v "%~2" /f >nul 2>>"%LOGFILE%"
set "DeleteValueRC=%ERRORLEVEL%"
if not "%DeleteValueRC%"=="0" (
    for %%R in ("%DeleteValueRC%") do (
        if defined TBOK_PROFILE_SUMMARY_MODE (
            endlocal & set /a "TBOK_PROFILE_FAILED+=1" >nul 2>&1
            call :LOG ERROR: Failed to delete %~3. Exit code: %%~R.
        ) else (
            endlocal
            call :LOG ERROR: Failed to delete %~3. Exit code: %%~R.
        )
        exit /b 1
    )
)
if defined TBOK_PROFILE_SUMMARY_MODE (
    endlocal & set /a "TBOK_PROFILE_APPLIED+=1" >nul 2>&1
) else (
    endlocal
    call :LOG Deleted %~3.
)
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


:ResolveSystemPolicy
:: Resolve all hardware-dependent targets only after the hardware profile
:: has completed successfully.
if defined TBOK_POLICY_ALREADY_RESOLVED exit /b 0
if not defined TBOK_SYSTEM_PROFILE_READY (
    call :LOG ERROR: The complete hardware profile is unavailable.
    call :LOG Hardware-dependent system policies were not resolved.
    exit /b 1
)
set "TBOK_SYSMAIN_MODE=unchanged"
set "TBOK_MMAGENT_POLICY=Unchanged"
set "TBOK_PREFETCH_POLICY=Unchanged"
set "TBOK_LOW_MEMORY_POLICY=No"
set "TBOK_HIBERNATION_POLICY=Unchanged"
set "TBOK_PAGEFILE_POLICY=Unchanged"
set "TBOK_PAGEFILE_INITIAL_MB="
set "TBOK_PAGEFILE_MAXIMUM_MB="
set "TBOK_POWERPLAN_POLICY=Unchanged"

if not defined TBOK_MEMORY_MB (
    call :LOG ERROR: Installed RAM is unavailable.
    call :LOG Hardware-dependent policy targets could not be resolved.
    exit /b 1
)

if not defined TBOK_MEMORY_GB set "TBOK_MEMORY_GB=Unknown"
if not defined TBOK_DRIVETYPE set "TBOK_DRIVETYPE=UNKNOWN"
if not defined CHASSISTYPE set "CHASSISTYPE=Unknown"

:: Hibernation and Gaming power-plan policies.
if /I "!CHASSISTYPE!"=="Laptop" (
    set "TBOK_HIBERNATION_POLICY=Enabled"
    set "TBOK_POWERPLAN_POLICY=Current"
) else if /I "!CHASSISTYPE!"=="Desktop" (
    set "TBOK_HIBERNATION_POLICY=Disabled"
    set "TBOK_POWERPLAN_POLICY=Ultimate Performance"
)

:: Resolve SysMain, MMAgent, and Windows Prefetch policy.
::
:: RAM <= 12 GB:
::   Keep SysMain Automatic so MMAgent remains functional.
::   Enable the low-memory MMAgent policy.
::   Use boot prefetch only to reduce application-launch memory pressure.
::
:: RAM > 12 GB:
::   SSD     = SysMain Automatic, boot prefetch only.
::   HDD     = SysMain Automatic, boot + application prefetch.
::   Unknown = SysMain and Prefetch left unchanged.

if !TBOK_MEMORY_MB! LEQ 12288 (
    set "TBOK_LOW_MEMORY_POLICY=Yes"
    set "TBOK_MMAGENT_POLICY=Enabled"
    set "TBOK_SYSMAIN_MODE=auto"
    set "TBOK_PREFETCH_POLICY=2"
) else if /I "!TBOK_DRIVETYPE!"=="SSD" (
    set "TBOK_SYSMAIN_MODE=auto"
    set "TBOK_PREFETCH_POLICY=2"
) else if /I "!TBOK_DRIVETYPE!"=="HDD" (
    set "TBOK_SYSMAIN_MODE=auto"
    set "TBOK_PREFETCH_POLICY=3"
)


:: Page-file policy.
if !TBOK_MEMORY_MB! GEQ 32768 (
    set "TBOK_PAGEFILE_POLICY=Unchanged"
) else if !TBOK_MEMORY_MB! LSS 8192 (
    set "TBOK_PAGEFILE_INITIAL_MB=4096"
    set "TBOK_PAGEFILE_MAXIMUM_MB=16384"
    set "TBOK_PAGEFILE_POLICY=4096-16384 MB"
) else if !TBOK_MEMORY_MB! LSS 16384 (
    set "TBOK_PAGEFILE_INITIAL_MB=8192"
    set "TBOK_PAGEFILE_MAXIMUM_MB=24576"
    set "TBOK_PAGEFILE_POLICY=8192-24576 MB"
) else (
    set "TBOK_PAGEFILE_INITIAL_MB=8192"
    set "TBOK_PAGEFILE_MAXIMUM_MB=32768"
    set "TBOK_PAGEFILE_POLICY=8192-32768 MB"
)

call :LOG Resolved system policy:
call :LOG Installed RAM: !TBOK_MEMORY_MB! MB
call :LOG Storage profile: !TBOK_DRIVETYPE!
call :LOG Chassis profile: !CHASSISTYPE!
call :LOG Low-memory policy: !TBOK_LOW_MEMORY_POLICY!
call :LOG SysMain target: !TBOK_SYSMAIN_MODE!
call :LOG MMAgent target: !TBOK_MMAGENT_POLICY!
call :LOG Prefetch target: !TBOK_PREFETCH_POLICY!
call :LOG Hibernation target: !TBOK_HIBERNATION_POLICY!
call :LOG Page-file target: !TBOK_PAGEFILE_POLICY!
call :LOG Gaming power-plan target: !TBOK_POWERPLAN_POLICY!
call :ShowAnalysisProgress 100 "Optimization policy ready"
set "TBOK_POLICY_ALREADY_RESOLVED=1"
exit /b 0

:: Configure MMAgent features only for the low-memory profile.
:ConfigureMemoryFeatures
if /I not "!TBOK_MMAGENT_POLICY!"=="Enabled" (
    call :LOG MMAgent settings were left unchanged by the resolved system policy.
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

:: Security: the snapshot lists process names, which any local user controls. Copy the
:: file as data rather than passing each line through CALL :LOG, so a process whose name
:: contains & cannot inject a command into this elevated session.
if exist "%TBOK_MEMORY_FILE%" (
    if not defined TBOK_ANALYSIS_PROGRESS_ACTIVE type "%TBOK_MEMORY_FILE%"
    >>"%LOGFILE%" type "%TBOK_MEMORY_FILE%"
    del /q "%TBOK_MEMORY_FILE%" >nul 2>&1
)
if not "%TBOK_MEMORY_RC%"=="0" (
    for %%R in ("%TBOK_MEMORY_RC%") do (
        endlocal
        call :LOG WARNING: Memory snapshot "%~1" failed with exit code %%~R.
        exit /b 1
    )
)

endlocal
exit /b 0

:GetChassisType
:: Helper for Chassis type detection to avoid enabling desktop tweaks on a device with a battery - Returns Laptop, Desktop, or Unknown in CHASSISTYPE for later logic use
set "CHASSISTYPE=Unknown"
for /f "delims=" %%G in ('powershell.exe -NoProfile -Command "$ct=@((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes); if($null -ne ($ct -as [array])){if($ct -match '^(8|9|10|11|12|14|18|21|30|31|32)$'){'Laptop'}elseif($ct -match '^(3|4|5|6|7|13|15|16|24|35|36)$'){'Desktop'}else{'Unknown'}}else{'Unknown'}" 2^>nul') do set "CHASSISTYPE=%%G"
exit /b

:GetSystemProfile
:: Helper to build variables required hardware profile for specific scenario optimizations.
:: Cache the profile only after all required detection completed successfully.
if defined TBOK_SYSTEM_PROFILE_READY exit /b 0

set "SystemProfileFailed=0"
set "TBOK_SYSTEM_PROFILE_READY="
call :ShowAnalysisProgress 5 "Initializing hardware profile"
call :LOG Building hardware profile...
call :GetInstalledMemory
set "SystemProfileMemoryRC=!ERRORLEVEL!"
if "!SystemProfileMemoryRC!"=="0" (
    call :ShowAnalysisProgress 20 "Installed memory detected"
) else (
    call :ShowAnalysisProgress 20 "Memory detection incomplete"
)
if not "!SystemProfileMemoryRC!"=="0" (
    set "SystemProfileFailed=1"
    call :LOG WARNING: Installed memory could not be determined.
)

call :GetChassisType
call :ShowAnalysisProgress 40 "Chassis profile detected"
call :LOG Chassis profile: !CHASSISTYPE!
::Detect whether the Windows system drive is an HDD or SSD and physical media type 
set "TBOK_DRIVETYPE=UNKNOWN"
set "DriveDetectRC="
set "DriveDetectFile=%TEMP%\TBOK-DriveDetect-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

call :LOG Detecting Windows system drive media type...
call :ShowAnalysisProgress 50 "Analyzing system drive"
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
    set "SystemProfileFailed=1"
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
call :ShowAnalysisProgress 75 "System drive profile detected"

:GetSystemProfileCleanup
if defined DriveDetectFile (
    if exist "%DriveDetectFile%" (
        del /q "%DriveDetectFile%" >nul 2>&1
    )
)
call :LOG Storage profile: !TBOK_DRIVETYPE!
if "!SystemProfileFailed!"=="1" (
    set "TBOK_SYSTEM_PROFILE_READY="
    set "SystemProfileFailed="
    exit /b 1
)

call :ShowAnalysisProgress 85 "Hardware profile complete"
set "TBOK_SYSTEM_PROFILE_READY=1"
set "SystemProfileFailed="
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
if defined TBOK_REMOTE_CONTROLLER (
    if exist "!TBOK_REMOTE_CONTROLLER!" (
        del /q "!TBOK_REMOTE_CONTROLLER!" >nul 2>&1
    )
)

if defined TBOK_REMOTE_CONTROLLER_RAW (
    if exist "!TBOK_REMOTE_CONTROLLER_RAW!" (
        del /q "!TBOK_REMOTE_CONTROLLER_RAW!" >nul 2>&1
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

:UnlockHiddenPowerSettings
call :LOG Unlocking all hidden Power Plan attributes
setlocal EnableDelayedExpansion
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
) >"!TBOK_POWER_UNLOCK!"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "!TBOK_POWER_UNLOCK!" >>"%LOGFILE%" 2>&1
set "PowerUnlockRC=!ERRORLEVEL!"

if exist "!TBOK_POWER_UNLOCK!" (
    del /q "!TBOK_POWER_UNLOCK!" >nul 2>&1
)
if not "!PowerUnlockRC!"=="0" (
    endlocal
    call :LOG WARNING: Failed to unlock one or more hidden power settings.
    exit /b 1
)
endlocal
call :LOG Hidden power-plan settings unlocked successfully.
exit /b 0

:ConfigureProcessorBoostMode
setlocal EnableDelayedExpansion
set "BoostAC=%~1"
set "BoostDC=%~2"
set "BoostDescription=%~3"

powercfg.exe -attributes SUB_PROCESSOR PERFBOOSTMODE -ATTRIB_HIDE >>"%LOGFILE%" 2>&1
set "BoostAttributeRC=!ERRORLEVEL!"

powercfg.exe -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE !BoostAC! >>"%LOGFILE%" 2>&1
set "BoostACRC=!ERRORLEVEL!"

powercfg.exe -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE !BoostDC! >>"%LOGFILE%" 2>&1
set "BoostDCRC=!ERRORLEVEL!"

powercfg.exe -setactive SCHEME_CURRENT >>"%LOGFILE%" 2>&1
set "BoostActivateRC=!ERRORLEVEL!"

if not "!BoostAttributeRC!!BoostACRC!!BoostDCRC!!BoostActivateRC!"=="0000" (
    endlocal
    call :LOG WARNING: Processor Performance Boost Mode configuration did not complete successfully.
    exit /b 1
)
endlocal
call :LOG Processor Performance Boost Mode configured: %~3.
exit /b 0

:DetectRemoteRequest
:: Detect /REMOTE or /REMOTELIST and preserve all operation switches.
:: /REMOTE and /REMOTELIST are mutually exclusive.
set "TBOK_REMOTE_HOST="
set "TBOK_REMOTE_LIST_FILE="
set "TBOK_REMOTE_OPERATION_ARGS="
set "TBOK_REMOTE_DESTINATION_FOUND=0"
set "TBOK_REMOTE_OPERATION_FOUND=0"

:DetectRemoteRequestNext
if "%~1"=="" goto :DetectRemoteRequestComplete

if /I "%~1"=="/REMOTE" (
    if "%~2"=="" (
        echo ERROR: /REMOTE requires a destination computer name.
        exit /b 2
    )

    if defined TBOK_REMOTE_LIST_FILE (
        echo ERROR: /REMOTE cannot be combined with /REMOTELIST.
        exit /b 2
    )

    if "!TBOK_REMOTE_DESTINATION_FOUND!"=="1" (
        echo ERROR: A remote destination was specified more than once.
        exit /b 2
    )

    set "TBOK_REMOTE_DESTINATION_FOUND=1"
    set "TBOK_REMOTE_HOST=%~2"

    shift
    shift
    goto :DetectRemoteRequestNext
)

if /I "%~1"=="/REMOTELIST" (
    if "%~2"=="" (
        echo ERROR: /REMOTELIST requires a computer-list file.
        exit /b 2
    )

    if defined TBOK_REMOTE_HOST (
        echo ERROR: /REMOTELIST cannot be combined with /REMOTE.
        exit /b 2
    )

    if "!TBOK_REMOTE_DESTINATION_FOUND!"=="1" (
        echo ERROR: A remote destination was specified more than once.
        exit /b 2
    )

    set "TBOK_REMOTE_DESTINATION_FOUND=1"
    set "TBOK_REMOTE_LIST_FILE=%~2"

    shift
    shift
    goto :DetectRemoteRequestNext
)

if /I "%~1"=="/OPTIMIZE" set "TBOK_REMOTE_OPERATION_FOUND=1"
if /I "%~1"=="/CLEANUP" set "TBOK_REMOTE_OPERATION_FOUND=1"
if /I "%~1"=="/GAMING" set "TBOK_REMOTE_OPERATION_FOUND=1"
if /I "%~1"=="/WINGET" set "TBOK_REMOTE_OPERATION_FOUND=1"

set "TBOK_REMOTE_OPERATION_ARGS=!TBOK_REMOTE_OPERATION_ARGS! %~1"

shift
goto :DetectRemoteRequestNext


:DetectRemoteRequestComplete
if "!TBOK_REMOTE_DESTINATION_FOUND!"=="0" (
    set "TBOK_REMOTE_OPERATION_ARGS="
    set "TBOK_REMOTE_OPERATION_FOUND="
    set "TBOK_REMOTE_DESTINATION_FOUND="
    exit /b 0
)

if "!TBOK_REMOTE_OPERATION_FOUND!"=="0" (
    echo ERROR: Remote execution requires at least one operation switch.
    echo.
    echo Single-computer example:
    echo %~nx0 /OPTIMIZE /REMOTE COMPUTER01
    echo.
    echo Multiple-computer example:
    echo %~nx0 /OPTIMIZE /REMOTELIST computers.txt
    exit /b 2
)

set "TBOK_REMOTE_OPERATION_ARGS=!TBOK_REMOTE_OPERATION_ARGS:~1!"
set "TBOK_REMOTE_OPERATION_FOUND="
set "TBOK_REMOTE_DESTINATION_FOUND="

exit /b 0

:BuildRemoteController
:: Extract the embedded PowerShell controller from this batch file.
set "TBOK_REMOTE_CONTROLLER=%TEMP%\TBOKRemoteController-%RANDOM%-%RANDOM%.ps1"
set "TBOK_REMOTE_CONTROLLER_RAW=%TEMP%\TBOKRemoteController-%RANDOM%-%RANDOM%.raw"
set "BuildRemoteControllerRC=1"

if exist "!TBOK_REMOTE_CONTROLLER!" (
    del /q "!TBOK_REMOTE_CONTROLLER!" >nul 2>&1
)

if exist "!TBOK_REMOTE_CONTROLLER_RAW!" (
    del /q "!TBOK_REMOTE_CONTROLLER_RAW!" >nul 2>&1
)

findstr /B /L /C:"::TBOK-REMOTE-PS::" "%~f0" >"!TBOK_REMOTE_CONTROLLER_RAW!"

if errorlevel 1 (
    echo ERROR: The embedded remote-controller payload was not found.
    set "TBOK_REMOTE_CONTROLLER="
    set "TBOK_REMOTE_CONTROLLER_RAW="
    exit /b 1
)

set "TBOK_REMOTE_CONTROLLER_RAW_ENV=!TBOK_REMOTE_CONTROLLER_RAW!"
set "TBOK_REMOTE_CONTROLLER_ENV=!TBOK_REMOTE_CONTROLLER!"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$prefix='::TBOK-REMOTE-PS::';$source=$env:TBOK_REMOTE_CONTROLLER_RAW_ENV;$destination=$env:TBOK_REMOTE_CONTROLLER_ENV;try{$lines=Get-Content -LiteralPath $source -ErrorAction Stop;$output=foreach($line in $lines){if($line.StartsWith($prefix)){$line.Substring($prefix.Length)}};Set-Content -LiteralPath $destination -Value $output -Encoding UTF8 -ErrorAction Stop;exit 0}catch{Write-Output ('ERROR: Remote controller creation failed: '+$_.Exception.Message);exit 1}"

set "BuildRemoteControllerRC=!ERRORLEVEL!"

set "TBOK_REMOTE_CONTROLLER_RAW_ENV="
set "TBOK_REMOTE_CONTROLLER_ENV="

if exist "!TBOK_REMOTE_CONTROLLER_RAW!" (
    del /q "!TBOK_REMOTE_CONTROLLER_RAW!" >nul 2>&1
)

set "TBOK_REMOTE_CONTROLLER_RAW="

if not "!BuildRemoteControllerRC!"=="0" (
    if exist "!TBOK_REMOTE_CONTROLLER!" (
        del /q "!TBOK_REMOTE_CONTROLLER!" >nul 2>&1
    )

    set "TBOK_REMOTE_CONTROLLER="
    echo ERROR: The remote controller could not be created.
    exit /b 1
)

if not exist "!TBOK_REMOTE_CONTROLLER!" (
    set "TBOK_REMOTE_CONTROLLER="
    echo ERROR: The generated remote-controller file was not found.
    exit /b 1
)

for %%F in ("!TBOK_REMOTE_CONTROLLER!") do (
    if %%~zF LEQ 0 (
        del /q "!TBOK_REMOTE_CONTROLLER!" >nul 2>&1
        set "TBOK_REMOTE_CONTROLLER="
        echo ERROR: The generated remote-controller file is empty.
        exit /b 1
    )
)

exit /b 0

:RunRemoteList
setlocal EnableExtensions EnableDelayedExpansion

set "RemoteListPath=!TBOK_REMOTE_LIST_FILE!"
set "RemoteListAttempted=0"
set "RemoteListSucceeded=0"
set "RemoteListFailed=0"
set "RemoteListSkipped=0"
set "RemoteListFailedHosts="

:: The script runs from System32 (see the security note at the top), so first resolve a
:: relative list path against the directory the script was launched from.
if exist "!TBOK_START_DIR!\!RemoteListPath!" (
    set "RemoteListPath=!TBOK_START_DIR!\!RemoteListPath!"
)

:: Resolve relative list paths beside the TBOK batch file.
if not exist "!RemoteListPath!" (
    if exist "%~dp0!RemoteListPath!" (
        set "RemoteListPath=%~dp0!RemoteListPath!"
    )
)

if not exist "!RemoteListPath!" (
    endlocal
    echo ERROR: Remote computer-list file was not found.
    echo Requested file: %TBOK_REMOTE_LIST_FILE%
    exit /b 2
)

echo.
echo ================================================================
echo TBOK Multi-Computer Remote Optimization
echo ================================================================
echo Computer list : !RemoteListPath!
echo Operations    : !TBOK_REMOTE_OPERATION_ARGS!
echo Execution     : Sequential
echo ================================================================
echo.

for /f "usebackq tokens=* delims=" %%H in ("!RemoteListPath!") do (
    set "RemoteListHost=%%H"

    if not defined RemoteListHost (
        set /a "RemoteListSkipped+=1"
    ) else (
        if "!RemoteListHost:~0,1!"=="#" (
            set /a "RemoteListSkipped+=1"
        ) else (
            set /a "RemoteListAttempted+=1"
            set "TBOK_REMOTE_HOST=!RemoteListHost!"

            echo.
            echo ================================================================
            echo Remote computer !RemoteListAttempted!: !TBOK_REMOTE_HOST!
            echo ================================================================

            call :RunRemoteController
            set "RemoteHostRC=!ERRORLEVEL!"

            if "!RemoteHostRC!"=="0" (
                set /a "RemoteListSucceeded+=1"
                echo RESULT: !TBOK_REMOTE_HOST! completed successfully.
            ) else (
                set /a "RemoteListFailed+=1"
                set "RemoteListFailedHosts=!RemoteListFailedHosts! !TBOK_REMOTE_HOST!"
                echo RESULT: !TBOK_REMOTE_HOST! failed with exit code !RemoteHostRC!.
            )
        )
    )
)

echo.
echo ================================================================
echo TBOK Remote Deployment Summary
echo ================================================================
echo Computers attempted : !RemoteListAttempted!
echo Successful          : !RemoteListSucceeded!
echo Failed              : !RemoteListFailed!
echo Blank/comment lines : !RemoteListSkipped!

if not "!RemoteListFailed!"=="0" (
    echo Failed computers     :!RemoteListFailedHosts!
)

echo ================================================================
echo.

if "!RemoteListAttempted!"=="0" (
    endlocal
    echo ERROR: The remote computer-list file contained no computer names.
    exit /b 2
)

if not "!RemoteListFailed!"=="0" (
    endlocal
    exit /b 1
)

endlocal
exit /b 0

:RunRemoteController
call :BuildRemoteController
set "BuildRemoteControllerRC=!ERRORLEVEL!"

if not "!BuildRemoteControllerRC!"=="0" (
    exit /b !BuildRemoteControllerRC!
)

echo.
echo ================================================================
echo TBOK Remote Optimization
echo ================================================================
echo Destination : !TBOK_REMOTE_HOST!
echo Operations  : !TBOK_REMOTE_OPERATION_ARGS!
echo Local source: %~f0
echo Local output: %~dp0
echo ================================================================
echo.
set "TBOK_REMOTE_ARGUMENT_TEXT=!TBOK_REMOTE_OPERATION_ARGS!"
set "TBOK_LOCAL_OUTPUT_PATH=%~dp0"
:: Remove the trailing backslash before passing the path to PowerShell.
:: A quoted native argument ending in \" can consume the closing quote
:: and merge -ArgumentText parameter into the path.
if "!TBOK_LOCAL_OUTPUT_PATH:~-1!"=="\" (
    set "TBOK_LOCAL_OUTPUT_PATH=!TBOK_LOCAL_OUTPUT_PATH:~0,-1!"
)

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
    -File "!TBOK_REMOTE_CONTROLLER!" ^
    -ComputerName "!TBOK_REMOTE_HOST!" ^
    -BatchPath "%~f0" ^
    -LocalOutputPath "!TBOK_LOCAL_OUTPUT_PATH!" ^
    -ArgumentText "!TBOK_REMOTE_ARGUMENT_TEXT!"

set "RemoteControllerRC=!ERRORLEVEL!"
set "TBOK_LOCAL_OUTPUT_PATH="
set "TBOK_REMOTE_ARGUMENT_TEXT="

if exist "!TBOK_REMOTE_CONTROLLER!" (
    del /q "!TBOK_REMOTE_CONTROLLER!" >nul 2>&1
)

set "TBOK_REMOTE_CONTROLLER="

if not "!RemoteControllerRC!"=="0" (
    echo.
    echo ERROR: Remote TBOK execution returned exit code !RemoteControllerRC!.
    exit /b !RemoteControllerRC!
)

echo.
echo Remote TBOK execution completed successfully.
echo Retrieved remote log file was saved beside the local batch file.
exit /b 0

::TBOK-REMOTE-PS::[CmdletBinding()]
::TBOK-REMOTE-PS::param(
::TBOK-REMOTE-PS::    [Parameter(Mandatory = $true)]
::TBOK-REMOTE-PS::    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
::TBOK-REMOTE-PS::    [string]$ComputerName,
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    [Parameter(Mandatory = $true)]
::TBOK-REMOTE-PS::    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
::TBOK-REMOTE-PS::    [string]$BatchPath,
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    [Parameter(Mandatory = $true)]
::TBOK-REMOTE-PS::    [string]$LocalOutputPath,
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    [Parameter(Mandatory = $true)]
::TBOK-REMOTE-PS::    [string]$ArgumentText
::TBOK-REMOTE-PS::)
::TBOK-REMOTE-PS::    Write-Host ('ArgumentText = [' + $ArgumentText + ']')
::TBOK-REMOTE-PS::    Write-Host ('LocalOutputPath = [' + $LocalOutputPath + ']')

::TBOK-REMOTE-PS::$ErrorActionPreference = 'Stop'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::# Set after the session opens: a new private folder per run (see below).
::TBOK-REMOTE-PS::$remoteDirectory = $null
::TBOK-REMOTE-PS::$remoteBatchName = Split-Path -Leaf $BatchPath
::TBOK-REMOTE-PS::$remoteBatchPath = $null
::TBOK-REMOTE-PS::$session = $null
::TBOK-REMOTE-PS::$remoteExitCode = 1
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::$arguments = @(
::TBOK-REMOTE-PS::    $ArgumentText -split '\s+' |
::TBOK-REMOTE-PS::        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
::TBOK-REMOTE-PS::)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::$allowedArguments = @(
::TBOK-REMOTE-PS::    '/OPTIMIZE'
::TBOK-REMOTE-PS::    '/CLEANUP'
::TBOK-REMOTE-PS::    '/GAMING'
::TBOK-REMOTE-PS::    '/WINGET'
::TBOK-REMOTE-PS::    '/NEWLOG'
::TBOK-REMOTE-PS::    '/RESTART'
::TBOK-REMOTE-PS::)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::foreach ($argument in $arguments) {
::TBOK-REMOTE-PS::    if ($allowedArguments -notcontains $argument.ToUpperInvariant()) {
::TBOK-REMOTE-PS::        throw "Unsupported remote TBOK argument: $argument"
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::}
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::$restartRequested = $arguments -contains '/RESTART'
::TBOK-REMOTE-PS::$remoteArguments = @(
::TBOK-REMOTE-PS::    $arguments |
::TBOK-REMOTE-PS::        Where-Object { $_ -ine '/RESTART' }
::TBOK-REMOTE-PS::)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::try {
::TBOK-REMOTE-PS::    Write-Host "Connecting to $ComputerName..."
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $session = New-PSSession -ComputerName $ComputerName -ErrorAction Stop
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host 'Verifying remote administrative access...'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::        & "$env:SystemRoot\System32\fltmc.exe" *> $null
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        if ($LASTEXITCODE -ne 0) {
::TBOK-REMOTE-PS::            throw 'The remote PowerShell session does not have administrative rights.'
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host 'Preparing a private remote working directory...'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    # Security: standard users can create files and folders under C:\ProgramData.
::TBOK-REMOTE-PS::    # A fixed folder there with inherited permissions lets any local user pre-create
::TBOK-REMOTE-PS::    # it (and own it), plant executables in it, or replace the batch file between
::TBOK-REMOTE-PS::    # the copy and the elevated run. Create a new, randomly named folder whose ACL
::TBOK-REMOTE-PS::    # grants access only to SYSTEM and Administrators, set at creation time, and
::TBOK-REMOTE-PS::    # refuse to reuse a folder that already exists.
::TBOK-REMOTE-PS::    $remoteDirectory = Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::        $directory = Join-Path $env:ProgramData ('TBOK-' + [guid]::NewGuid().ToString('N'))
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        if (Test-Path -LiteralPath $directory) {
::TBOK-REMOTE-PS::            throw "Remote staging directory already exists: $directory"
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        $security = New-Object System.Security.AccessControl.DirectorySecurity
::TBOK-REMOTE-PS::        $security.SetAccessRuleProtection($true, $false)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
::TBOK-REMOTE-PS::            $identity = New-Object System.Security.Principal.SecurityIdentifier $sid
::TBOK-REMOTE-PS::            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule `
::TBOK-REMOTE-PS::                $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
::TBOK-REMOTE-PS::            $security.AddAccessRule($rule)
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        [void][System.IO.Directory]::CreateDirectory($directory, $security)
::TBOK-REMOTE-PS::        return $directory
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $remoteDirectory = [string]$remoteDirectory
::TBOK-REMOTE-PS::    $remoteBatchPath = Join-Path $remoteDirectory $remoteBatchName
::TBOK-REMOTE-PS::    Write-Host "Remote working directory: $remoteDirectory"
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host "Copying $remoteBatchName to $ComputerName..."
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Copy-Item `
::TBOK-REMOTE-PS::        -LiteralPath $BatchPath `
::TBOK-REMOTE-PS::        -Destination $remoteBatchPath `
::TBOK-REMOTE-PS::        -ToSession $session `
::TBOK-REMOTE-PS::        -Force
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host ('Starting remote operations: ' + ($remoteArguments -join ' '))
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $remoteExitCode = Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::        param(
::TBOK-REMOTE-PS::            $WorkingDirectory,
::TBOK-REMOTE-PS::            $RemoteBatch,
::TBOK-REMOTE-PS::            [string[]]$Arguments
::TBOK-REMOTE-PS::        )
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        $argumentLine = $Arguments -join ' '
::TBOK-REMOTE-PS::        $commandLine = '/d /c ""{0}" {1}"' -f $RemoteBatch, $argumentLine
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        $process = Start-Process `
::TBOK-REMOTE-PS::            -FilePath $env:ComSpec `
::TBOK-REMOTE-PS::            -ArgumentList $commandLine `
::TBOK-REMOTE-PS::            -WorkingDirectory $WorkingDirectory `
::TBOK-REMOTE-PS::            -NoNewWindow `
::TBOK-REMOTE-PS::            -Wait `
::TBOK-REMOTE-PS::            -PassThru
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        return [int]$process.ExitCode
::TBOK-REMOTE-PS::    } -ArgumentList $remoteDirectory, $remoteBatchPath, $remoteArguments
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host "Remote TBOK exit code: $remoteExitCode"
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host 'Locating remote TBOK log file...'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $logFile = Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::        param($Directory)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        Get-ChildItem `
::TBOK-REMOTE-PS::            -LiteralPath $Directory `
::TBOK-REMOTE-PS::            -Filter 'TBOKwinOptimizer-*.log' `
::TBOK-REMOTE-PS::            -File `
::TBOK-REMOTE-PS::            -ErrorAction SilentlyContinue |
::TBOK-REMOTE-PS::                Sort-Object LastWriteTime -Descending |
::TBOK-REMOTE-PS::                Select-Object -First 1
::TBOK-REMOTE-PS::    } -ArgumentList $remoteDirectory
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    if ($null -eq $logFile) {
::TBOK-REMOTE-PS::        throw 'No TBOK log file was found on the remote computer.'
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host ('Remote log identified: ' + $logFile.FullName)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $remoteLogPath = [string]$logFile.FullName
::TBOK-REMOTE-PS::    $remoteLogName = Split-Path -Leaf $remoteLogPath
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    $localLogFile = Join-Path `
::TBOK-REMOTE-PS::        $LocalOutputPath `
::TBOK-REMOTE-PS::        $remoteLogName
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host ('Remote path type : ' + $logFile.GetType().FullName)
::TBOK-REMOTE-PS::    Write-Host ('Remote path value: ' + $remoteLogPath)
::TBOK-REMOTE-PS::    Write-Host ('Remote file name : ' + $remoteLogName)
::TBOK-REMOTE-PS::    Write-Host ('Local output    : ' + $LocalOutputPath)
::TBOK-REMOTE-PS::    Write-Host ('Local log path  : ' + $localLogFile)
::TBOK-REMOTE-PS::    Write-Host ('Destination type : ' + $localLogFile.GetType().FullName)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Copy-Item `
::TBOK-REMOTE-PS::        -LiteralPath $remoteLogPath `
::TBOK-REMOTE-PS::        -Destination $localLogFile `
::TBOK-REMOTE-PS::        -FromSession $session `
::TBOK-REMOTE-PS::        -Force `
::TBOK-REMOTE-PS::        -ErrorAction Stop
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    if (-not (Test-Path -LiteralPath $localLogFile -PathType Leaf)) {
::TBOK-REMOTE-PS::        throw 'The remote log file was not copied to the local computer.'
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host ('Retrieved log file: ' + $localLogFile)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host 'Removing remote TBOK execution artifacts...'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::        param($Directory)
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        if (-not $Directory -or (Split-Path -Leaf $Directory) -notlike 'TBOK-*') { return }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
::TBOK-REMOTE-PS::            Where-Object { $_.Name -like 'TBOKwinOptimizer*.log' -or $_.Name -like '*.bat' } |
::TBOK-REMOTE-PS::                Remove-Item -Force -ErrorAction SilentlyContinue
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::        # Fallback registry backups (created when a restore point fails) are the
::TBOK-REMOTE-PS::        # rollback path for this machine, so keep them. The folder is readable only
::TBOK-REMOTE-PS::        # by SYSTEM and Administrators. Remove it only when nothing is left.
::TBOK-REMOTE-PS::        if (@(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction SilentlyContinue).Count -eq 0) {
::TBOK-REMOTE-PS::            Remove-Item -LiteralPath $Directory -Force -ErrorAction SilentlyContinue
::TBOK-REMOTE-PS::            return $null
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::        return $Directory
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    } -ArgumentList $remoteDirectory -ErrorAction Stop |
::TBOK-REMOTE-PS::        ForEach-Object {
::TBOK-REMOTE-PS::            if ($_) { Write-Host "Rollback backups were kept on $ComputerName in: $_" }
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    Write-Host 'Remote batch and log files removed successfully.'
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::    if ($restartRequested) {
::TBOK-REMOTE-PS::        if ($remoteExitCode -eq 0) {
::TBOK-REMOTE-PS::            Write-Host 'Artifacts retrieved successfully.'
::TBOK-REMOTE-PS::            Write-Host "Restarting $ComputerName in 5 seconds..."
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::            Invoke-Command -Session $session -ScriptBlock {
::TBOK-REMOTE-PS::                shutdown.exe /r /t 5 /f
::TBOK-REMOTE-PS::            }
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::        else {
::TBOK-REMOTE-PS::            Write-Warning '/RESTART was requested, but the remote TBOK run failed.'
::TBOK-REMOTE-PS::            Write-Warning 'The remote computer was not restarted.'
::TBOK-REMOTE-PS::        }
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::}
::TBOK-REMOTE-PS::catch {
::TBOK-REMOTE-PS::    Write-Error $_.Exception.Message
::TBOK-REMOTE-PS::    $remoteExitCode = 1
::TBOK-REMOTE-PS::}
::TBOK-REMOTE-PS::finally {
::TBOK-REMOTE-PS::    if ($null -ne $session) {
::TBOK-REMOTE-PS::        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
::TBOK-REMOTE-PS::    }
::TBOK-REMOTE-PS::}
::TBOK-REMOTE-PS::
::TBOK-REMOTE-PS::exit [int]$remoteExitCode

:END-SCRIPT-HELPERS

:RefreshMenuProfile
set "TBOK_ANALYSIS_PROGRESS_ACTIVE=1"

if not defined TBOK_SYSTEM_PROFILE_READY (
    call :GetSystemProfile
)

if defined TBOK_SYSTEM_PROFILE_READY (
    call :ResolveSystemPolicy
)

set "TBOK_ANALYSIS_PROGRESS_ACTIVE="

if not defined TBOK_MEMORY_GB set "TBOK_MEMORY_GB=Unknown"
if not defined TBOK_DRIVETYPE set "TBOK_DRIVETYPE=UNKNOWN"
if not defined CHASSISTYPE set "CHASSISTYPE=Unknown"
if not defined TBOK_SYSMAIN_MODE set "TBOK_SYSMAIN_MODE=unchanged"
if not defined TBOK_MMAGENT_POLICY set "TBOK_MMAGENT_POLICY=Unchanged"
if not defined TBOK_LOW_MEMORY_POLICY set "TBOK_LOW_MEMORY_POLICY=Unknown"
if not defined TBOK_HIBERNATION_POLICY set "TBOK_HIBERNATION_POLICY=Unchanged"
if not defined TBOK_PAGEFILE_POLICY set "TBOK_PAGEFILE_POLICY=Unchanged"
if not defined TBOK_POWERPLAN_POLICY set "TBOK_POWERPLAN_POLICY=Unchanged"
exit /b 0

:MENU
call :RefreshMenuProfile
TITLE TBOK Windows Performance Optimizer Version %version% %verdate%
::MAKE SOUND rundll32.exe cmdext.dll,MessageBeepStub
echo %CLR_WARN%                   Script now supports cmd line options for non-interactive sessions
echo %CLR_WARN%       or automation - run with /optimize /cleanup /gaming /winget /restart /newlog as options
echo %CLR_TITLE% ********************************************************    ****************************************
echo %CLR_MENU% *                THE BEARD OF KNOWLEDGE                *                 SYSTEM PROFILE
echo %CLR_TITLE% *                                                      *
echo %CLR_MENU% *      ::::::::::: :::::::::   ::::::::  :::    :::    *        Computer: %COMPUTERNAME%
echo %CLR_MENU% *         :+:     :+:    :+: :+:    :+: :+:   :+:      *        RAM:      !TBOK_MEMORY_GB! GB
echo %CLR_MENU% *        +:+     +:+    +:+ +:+    +:+ +:+  +:+        *        Storage:  !TBOK_DRIVETYPE!
echo %CLR_MENU% *       +#+     +#++:++#+  +#+    +:+ +#++:++          *        Chassis:  !CHASSISTYPE!
echo %CLR_MENU% *      +#+     +#+    +#+ +#+    +#+ +#+  +#+          *
echo %CLR_MENU% *     #+#     #+#    #+# #+#    #+# #+#   #+#          *
echo %CLR_MENU% *    ###     #########   ########  ###    ###          *
echo %CLR_TITLE% *                                                      *
echo %CLR_TITLE% *           Windows Performance Optimizer              *
echo %CLR_TITLE% *           Version %version% %verdate%                   *
echo %CLR_TITLE% ********************************************************    ****************************************
echo %CLR_TITLE% *                                                      *                 Target Config:
echo %CLR_TITLE% *                                                      *
echo %CLR_OPTION% *     Please type the number for option:               *        Low Ram Policy: !TBOK_LOW_MEMORY_POLICY! 
echo %CLR_OPTION% *  1. Optimize system *START HERE                      *        Sysmain target: !TBOK_SYSMAIN_MODE!
echo %CLR_OPTION% *  2. Run BeardSweeper Disk Cleanup routine            *        MMAgent target mode: !TBOK_MMAGENT_POLICY!   
echo %CLR_OPTION% *  3. Apply Gaming Optimizations                       *        VM config target mode: !TBOK_PAGEFILE_POLICY!
echo %CLR_OPTION% *  4. Update apps using WinGet                         *        Hibernation target mode: !TBOK_HIBERNATION_POLICY!
echo %CLR_OPTION% *  5. EXIT                                             *        Gaming plan: !TBOK_POWERPLAN_POLICY!
echo %CLR_TITLE% *                                                      *
echo %CLR_warn% *      IF THIS HELPED YOU OUT -Buy me a coffee         *          Log Reuse Enabled
echo %CLR_warn% *      "https://buymeacoffee.com/thebeardofl"          *
echo %CLR_TITLE% ********************************************************    ****************************************
echo %CLR_RESET%
choice.exe /c 12345 /n /m "Enter 1-5: (Default: 1 in 30 seconds): " /t 30 /d 1 2>>"%LOGFILE%"
set "MenuChoiceRC=%ERRORLEVEL%"
color f0
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
call :ResolveSystemPolicy
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
if /I "!TBOK_HIBERNATION_POLICY!"=="Enabled" (
    call :LOG Laptop policy detected. Enabling hibernation and Fast Startup.
    powercfg.exe /hibernate on >nul 2>&1
) else if /I "!TBOK_HIBERNATION_POLICY!"=="Disabled" (
    call :LOG Desktop policy detected. Disabling hibernation and Fast Startup.
    powercfg.exe /hibernate off >nul 2>&1
) else (
    call :LOG Hibernation policy is unchanged because chassis type could not be determined.
)

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

if /I "!TBOK_PAGEFILE_POLICY!"=="Unchanged" (
    call :LOG Resolved page-file policy is Unchanged.
    call :LOG Page-file management mode, locations, and sizes were left unchanged.
    goto :SERVICES
)
set "PageFileInitialMB=!TBOK_PAGEFILE_INITIAL_MB!"
set "PageFileMaximumMB=!TBOK_PAGEFILE_MAXIMUM_MB!"

if not defined PageFileInitialMB (
    call :LOG ERROR: The resolved page-file initial size is unavailable.
    goto :SERVICES
)
if not defined PageFileMaximumMB (
    call :LOG ERROR: The resolved page-file maximum size is unavailable.
    goto :SERVICES
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
:: TBOK SysMain and Prefetch policy:
:: Systems with 12 GB or less RAM keep SysMain Automatic and use boot-only Prefetch.
:: Higher-memory SSD systems keep SysMain Automatic and use boot-only Prefetch.
:: Higher-memory HDD systems keep SysMain Automatic and use boot + application Prefetch.
:: Higher-memory systems with unknown storage leave SysMain and Prefetch unchanged.
call :LOG Installed RAM: !TBOK_MEMORY_MB! MB
call :LOG Storage profile: !TBOK_DRIVETYPE!
call :LOG Low-memory policy: !TBOK_LOW_MEMORY_POLICY!
call :LOG SysMain target mode: !TBOK_SYSMAIN_MODE!

if /I "!TBOK_SYSMAIN_MODE!"=="auto" (
    call :LOG Keeping SysMain Automatic according to the resolved system policy.
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
call :SetServiceStartup AppMgmt demand
call :SetServiceStartup AppReadiness demand
call :SetServiceStartup Appinfo demand
call :SetServiceStartup AssignedAccessManagerSvc demand
call :SetServiceStartup AxInstSV demand
call :SetServiceStartup BDESVC demand
call :SetServiceStartup BTAGService demand
call :SetServiceStartup bthserv demand
call :SetServiceStartup CertPropSvc demand
call :SetServiceStartup cloudidsvc demand
call :SetServiceStartup COMSysApp demand
call :SetServiceStartup CscService demand
call :SetServiceStartup DcpSvc demand
call :SetServiceStartup dcsvc demand
call :SetServiceStartup defragsvc demand
call :SetServiceStartup DevQueryBroker demand
call :SetServiceStartup DeviceAssociationService demand
call :SetServiceStartup DeviceInstall demand
call :SetServiceStartup diagnosticshub.standardcollector.service demand
call :SetServiceStartup diagsvc demand
call :SetServiceStartup DisplayEnhancementService demand
call :SetServiceStartup DmEnrollmentSvc demand
call :SetServiceStartup dmwappushservice demand
call :SetServiceStartup dot3svc demand
call :SetServiceStartup fdPHost demand
call :SetServiceStartup fhsvc demand
call :SetServiceStartup hidserv demand
call :SetServiceStartup icssvc demand
call :SetServiceStartup EapHost demand
call :SetServiceStartup edgeupdate demand
call :SetServiceStartup edgeupdatem demand
call :SetServiceStartup EFS demand
call :SetServiceStartup FDResPub demand
call :SetServiceStartup Fax demand
call :SetServiceStartup FrameServer demand
call :SetServiceStartup FrameServerMonitor demand
call :SetServiceStartup GraphicsPerfSvc demand
call :SetServiceStartup HvHost demand
call :SetServiceStartup IEEtwCollectorService demand
call :SetServiceStartup IpxlatCfgSvc demand
call :SetServiceStartup lfsvc demand
call :SetServiceStartup lltdsvc demand
call :SetServiceStartup lmhosts demand
call :SetServiceStartup LxpSvc demand
call :SetServiceStartup McpManagementService demand
call :SetServiceStartup MicrosoftEdgeElevationService demand
call :SetServiceStartup MixedRealityOpenXRSvc demand
call :SetServiceStartup MSDTC demand
call :SetServiceStartup MsKeyboardFilter demand
call :SetServiceStartup MSiSCSI demand
call :SetServiceStartup NaturalAuthentication demand
call :SetServiceStartup NcaSvc demand
call :SetServiceStartup NcbService demand
call :SetServiceStartup NcdAutoSetup demand
call :SetServiceStartup NetSetupSvc demand
call :SetServiceStartup Netman demand
call :SetServiceStartup p2pimsvc demand
call :SetServiceStartup p2psvc demand
call :SetServiceStartup PcaSvc demand
call :SetServiceStartup PeerDistSvc demand
call :SetServiceStartup perceptionsimulation demand
call :SetServiceStartup PerfHost demand
call :SetServiceStartup PhoneSvc demand
call :SetServiceStartup pla demand
call :SetServiceStartup PlugPlay demand
call :SetServiceStartup PNRPAutoReg demand
call :SetServiceStartup PNRPsvc demand
call :SetServiceStartup PolicyAgent demand
call :SetServiceStartup PrintNotify demand
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
call :SetServiceStartup TabletInputService demand
call :SetServiceStartup TapiSrv demand
call :SetServiceStartup TieringEngineService demand
call :SetServiceStartup TimeBroker demand
call :SetServiceStartup TroubleshootingSvc demand
call :SetServiceStartup tzautoupdate demand
call :SetServiceStartup UI0Detect demand
call :SetServiceStartup upnphost demand
call :SetServiceStartup VacSvc demand
call :SetServiceStartup vds demand
call :SetServiceStartup vmicguestinterface demand
call :SetServiceStartup vmicheartbeat demand
call :SetServiceStartup vmickvpexchange demand
call :SetServiceStartup vmicshutdown demand
call :SetServiceStartup vmictimesync demand
call :SetServiceStartup vmicvmsession demand
call :SetServiceStartup vmicvss demand
call :SetServiceStartup VSS demand
call :SetServiceStartup WalletService demand
call :SetServiceStartup wbengine demand
call :SetServiceStartup WcsPlugInService demand
call :SetServiceStartup wcncsvc demand
call :SetServiceStartup WdiServiceHost demand
call :SetServiceStartup WdiSystemHost demand
call :SetServiceStartup WebClient demand
call :SetServiceStartup Wecsvc demand
call :SetServiceStartup wercplsupport demand
call :SetServiceStartup WEPHOSTSVC demand
call :SetServiceStartup WerSvc demand
call :SetServiceStartup WFDSConMgrSvc demand
call :SetServiceStartup WiaRpc demand
call :SetServiceStartup wisvc demand
call :SetServiceStartup wlidsvc demand
call :SetServiceStartup wlpasvc demand
call :SetServiceStartup wmiApSrv demand
call :SetServiceStartup WMPNetworkSvc demand
call :SetServiceStartup WManSvc demand
call :SetServiceStartup WPDBusEnum demand
call :SetServiceStartup WpcMonSvc demand
call :SetServiceStartup workfolderssvc demand
call :SetServiceStartup wuauserv demand
call :SetServiceStartup XblAuthManager demand
call :SetServiceStartup XblGameSave demand
call :SetServiceStartup XboxGipSvc demand
call :SetServiceStartup XboxNetApiSvc demand
::protectedCOREservice call :SetServiceStartup AppIDSvc demand
::ignored call :SetServiceStartup BcastDVRUserService_* demand
::ignored call :SetServiceStartup BluetoothUserService_* demand
::deprecated call :SetServiceStartup 'Browser' demand
::ignored call :SetServiceStartup CaptureService_* demand
::ignored call :SetServiceStartup cbdhsvc_* demand
::deprecated call :SetServiceStartup CDPSvc demand
::protectedCOREservice call :SetServiceStartup ClipSVC demand
::ignored call :SetServiceStartup ConsentUxUserSvc_* demand
::ignored call :SetServiceStartup CredentialEnrollmentManagerUserSvc_* demand
::ignored call :SetServiceStartup DeviceAssociationBroker_* demand
::ignored call :SetServiceStartup DevicePickerUserSvc_* demand
::ignored call :SetServiceStartup DevicesFlowUserSvc_* demand
::protectedCOREservice call :SetServiceStartup DoSvc demand
::protectedCOREservice call :SetServiceStartup embeddedmode demand
::protectedCOREservice call :SetServiceStartup EntAppSvc demand
::deprecated call :SetServiceStartup  HomeGroupListener demand
::deprecated call :SetServiceStartup  HomeGroupProvider demand
::omitforEnterprise IPsec and VPN call :SetServiceStartup IKEEXT demand
::ignored call :SetServiceStartup InstallService demand
::ignored call :SetServiceStartup LicenseManager demand
::ignored call :SetServiceStartup MessagingService_* demand
::protectedCOREservice call :SetServiceStartup msiserver demand
::ignored call :SetServiceStartup NPSMSvc_* demand
::protectedCOREservice call :SetServiceStartup NgcCtnrSvc demand
::protectedCOREservice call :SetServiceStartup NgcSvc demand
::omitforENTERPRISE call :SetServiceStartup NlaSvc demand
::omitforENTERPRISE call :SetServiceStartup netprofm demand
::ignored call :SetServiceStartup P9RdrService_* demand
::ignored call :SetServiceStartup PenService_* demand
::ignored call :SetServiceStartup PimIndexMaintenanceSvc_* demand
::ignored call :SetServiceStartup PrintWorkflowUserSvc_* demand
::omitforENTERPRISE RDP call :SetServiceStartup SessionEnv demand
::protectedCOREservice call :SetServiceStartup TimeBrokerSvc demand
::omitforENTERPRISE call :SetServiceStartup TokenBroker demand
::ignored call :SetServiceStartup UdkUserSvc_* demand
::omitforENTERPRISE RDP call :SetServiceStartup UmRdpService demand
::ignored call :SetServiceStartup UnistoreSvc_* demand
::ignored call :SetServiceStartup UserDataSvc_* demand
::omitforENTERPRISE call :SetServiceStartup UsoSvc demand
::omitforENTERPRISE RDP call :SetServiceStartup vmicrdv demand
::protectedCOREservice call :SetServiceStartup WdNisSvc demand
::protectedCOREservice call :SetServiceStartup WinHttpAutoProxySvc demand
::omitforENTERPRISE call :SetServiceStartup WinRM demand
::omitforENTERPRISE call :SetServiceStartup WpnService demand
::deprecated call :SetServiceStartup  WSService demand
call :LOG Done with manual services
ECHO.

:windowsserviceauto
ECHO.
call :LOG Ensuring required services are set to automatic State
call :LOG This is just in case you used a previous utility that set the services incorrectly
call :SetServiceStartup AudioEndpointBuilder auto
call :SetServiceStartup AudioSrv auto
call :SetServiceStartup BthHFSrv auto
call :SetServiceStartup CryptSvc auto
call :SetServiceStartup DPS auto
call :SetServiceStartup Dhcp auto
call :SetServiceStartup DispBrokerDesktopSvc auto
call :SetServiceStartup dusmsvc auto
call :SetServiceStartup EventLog auto
call :SetServiceStartup EventSystem auto
call :SetServiceStartup FontCache auto
call :SetServiceStartup iphlpsvc auto
call :SetServiceStartup LanmanServer auto
call :SetServiceStartup LanmanWorkstation auto
call :SetServiceStartup nsi auto
call :SetServiceStartup Power auto
call :SetServiceStartup ProfSvc auto
call :SetServiceStartup SENS auto
call :SetServiceStartup SamSs auto
call :SetServiceStartup ShellHWDetection auto
call :SetServiceStartup Spooler auto
call :SetServiceStartup Themes auto
call :SetServiceStartup tiledatamodelsvc auto
call :SetServiceStartup TrkWks auto
call :SetServiceStartup uhssvc auto
call :SetServiceStartup UserManager auto
call :SetServiceStartup Wcmsvc auto
call :SetServiceStartup Winmgmt auto
call :SetServiceStartup WlanSvc auto
::protectedCOREservice call :SetServiceStartup BFE auto
::protectedCOREservice call :SetServiceStartup BrokerInfrastructure auto
::ignored call :SetServiceStartup CDPUserSvc_* auto
::protectedCOREservice call :SetServiceStartup CoreMessagingRegistrar auto
::protectedCOREservice call :SetServiceStartup DcomLaunch auto
::protectedCOREservice call :SetServiceStartup Dnscache auto
::protectedCOREservice call :SetServiceStartup gpsvc auto
::protectedCOREservice call :SetServiceStartup LSM auto
::protectedCOREservice call :SetServiceStartup MpsSvc auto
::ignored call :SetServiceStartup OneSyncSvc_* auto
::protectedCOREservice call :SetServiceStartup RpcEptMapper auto
::protectedCOREservice call :SetServiceStartup RpcSs auto
::omitforENTERPRISE call :SetServiceStartup RemoteAccess auto
::omitforENTERPRISE call :SetServiceStartup RemoteRegistry auto
::protectedCOREservice call :SetServiceStartup Schedule auto
::protectedCOREservice call :SetServiceStartup sppsvc auto
::protectedCOREservice call :SetServiceStartup SystemEventsBroker auto
::ignore due to possible conflict with third-party antivitus call :SetServiceStartup WinDefend auto
::ignored call :SetServiceStartup WpnUserService_* auto
call :LOG Auto services complete
ECHO.

:windowsservicedelayedauto
Call :LOG Changing less essential services to delayed-auto
call :SetServiceStartup BITS delayed-auto
call :SetServiceStartup W32Time delayed-auto
call :SetServiceStartup WSearch delayed-auto
call :SetServiceStartup wudfsvc delayed-auto
::omit call :SetServiceStartup MapsBroker delayed-auto
::protectedCOREservice call :SetServiceStartup SecurityHealthService delayed-auto
::protectedCOREservice call :SetServiceStartup wscsvc delayed-auto
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
echo(


call :LOG Applying resolved Windows Prefetch policy
if /I "!TBOK_PREFETCH_POLICY!"=="Unchanged" (
    call :LOG Windows Prefetch configuration was left unchanged.
) else (
    call :SetRegistryValue "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" "REG_DWORD" "!TBOK_PREFETCH_POLICY!" "Windows EnablePrefetcher"
)

call :LOG Disabling network throttling
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "REG_DWORD" "0xffffffff" "NetworkThrottlingIndex"

call :LOG Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
call :SetAllControlSetValues "Services\LanmanServer\Parameters" "IRPStackSize" "REG_DWORD" "30" "IRPStackSize"

call :LOG Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
call :SetRegistryValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" "REG_DWORD" "10" "SystemResponsiveness"

call :LOG Speed up shutdown time
call :SetAllControlSetValues "Control" "WaitToKillServiceTimeout" "REG_SZ" "3000" "WaitToKillServiceTimeout"

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

:ResetProfileCounters
set "TBOK_PROFILE_APPLIED=0"
set "TBOK_PROFILE_SKIPPED=0"
set "TBOK_PROFILE_FAILED=0"
exit /b 0

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
if defined TBOK_PROFILE_SUMMARY_MODE (
    if not "!TBOK_PROFILE_FAILED!"=="0" (
        exit /b 1
    )
)
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
if not defined TBOK_PROFILE_SETTINGS_LISTED (
    call :LOG ===========================================================
    call :LOG Applying User Registry Policy Set
    call :LOG ===========================================================
    call :LOG Explorer and folder-view behavior
    call :LOG Taskbar and Start menu preferences
    call :LOG Search and Bing integration
    call :LOG Background application controls
    call :LOG Gaming and Game Mode preferences
    call :LOG Visual effects and menu responsiveness
    call :LOG Advertising and content-delivery controls
    call :LOG Copilot and cross-device controls
    call :LOG Microsoft Office telemetry and logging
    call :LOG Accessibility hotkey preferences
    call :LOG ===========================================================
    set "TBOK_PROFILE_SETTINGS_LISTED=1"
)
:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :LOG Processing loaded user hives
set "LoadedUserHiveCount=0"
set "LoadedUserSettingsRC="

for /f "delims=" %%U in ('REG query HKEY_USERS 2^>nul ^| findstr /B /I /L /C:"HKEY_USERS\S-1-5-21-" /C:"HKEY_USERS\S-1-12-1-" ^| findstr /V /I /C:"_Classes"') do (
    set /a "LoadedUserHiveCount+=1"

    call :ResetProfileCounters
    set "TBOK_PROFILE_SUMMARY_MODE=1"

    call :ApplySettings "%%U"
    set "LoadedUserSettingsRC=!ERRORLEVEL!"

    set "TBOK_PROFILE_SUMMARY_MODE="

    call :LOG PROFILE SUMMARY: %%U
    call :LOG     Applied : !TBOK_PROFILE_APPLIED!
    call :LOG     Skipped : !TBOK_PROFILE_SKIPPED!
    call :LOG     Failed  : !TBOK_PROFILE_FAILED!

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

                        call :ResetProfileCounters
                        set "TBOK_PROFILE_SUMMARY_MODE=1"
                        call :ApplySettings "HKU\TempHive"
                        set "ProfileSettingsRC=!ERRORLEVEL!"
                        set "TBOK_PROFILE_SUMMARY_MODE="
                        call :LOG PROFILE SUMMARY: !PROFILE_PATH!
                        call :LOG     Applied : !TBOK_PROFILE_APPLIED!
                        call :LOG     Skipped : !TBOK_PROFILE_SKIPPED!
                        call :LOG     Failed  : !TBOK_PROFILE_FAILED!

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

        call :ResetProfileCounters
        set "TBOK_PROFILE_SUMMARY_MODE=1"
        call :ApplySettings "HKU\DefaultHive"
        set "DefaultSettingsRC=!ERRORLEVEL!"
        set "TBOK_PROFILE_SUMMARY_MODE="
        call :LOG PROFILE SUMMARY: Default Profile
        call :LOG     Applied : !TBOK_PROFILE_APPLIED!
        call :LOG     Skipped : !TBOK_PROFILE_SKIPPED!
        call :LOG     Failed  : !TBOK_PROFILE_FAILED!

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
if not defined TBOK_POWERPLAN_POLICY (
    call :GetSystemProfile
    if errorlevel 1 (
        call :LOG WARNING: The hardware profile could not be completed for Gaming.
    )
    call :ResolveSystemPolicy
    if errorlevel 1 (
        call :LOG WARNING: The Gaming power policy could not be resolved.
    )
)

call :LOG ****************************************************************
call :LOG        Begin Gaming Improvements        
call :LOG ****************************************************************


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

call :LOG Requesting Hardware Accelerated GPU Scheduling -HAGS- where supported by the installed GPU and driver.
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

call :LOG Detected chassis category: !CHASSISTYPE!
call :LOG Resolved Gaming power-plan policy: !TBOK_POWERPLAN_POLICY!

if /I "!TBOK_POWERPLAN_POLICY!"=="Current" goto :laptopgaming
if /I "!TBOK_POWERPLAN_POLICY!"=="Ultimate Performance" goto :desktopgaming
goto :unknownchassisgaming

:laptopgaming
call :LOG Laptop detected - desktop-only power tweaks were skipped.

call :UnlockHiddenPowerSettings
if errorlevel 1 (
    call :LOG WARNING: Gaming continued without completing the global power-setting unlock.
)

call :ConfigureProcessorBoostMode 3 3 "Efficient Aggressive"

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
call :ConfigureProcessorBoostMode 2 2 "Aggressive at Guaranteed"

call :UnlockHiddenPowerSettings
if errorlevel 1 (
    call :LOG WARNING: Gaming continued without completing the global power-setting unlock.
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
echo(
exit /b 0

:WinGet
call :LOG CAUTION - WINGET DOES NOT CONTROL PACKAGES WITH REBOOT AUTO ENABLED
call :LOG CAUTION - RUNNING THIS ON A REMOTE MACHINE COULD REBOOT THE PC AS PART OF THE SOFTWARE UPDATE PROCESS
call :LOG CAUTION - IT IS DEFAULTED TO NOT REBOOT BUT SOME PACKAGES IGNORE THE REQUEST
call :LOG CAUTION - MICROSOFT IS SUPPOSEDLY WORKING TO RESOLVE THIS WITH 3RD PARTY PACKAGE MANAGERS
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


:BEARDSWEEPERHELPERS

:PrepareApplicationForCleanup
:: Usage:
:: call :PrepareApplicationForCleanup "process.exe" "Application Name"
::
:: Return codes:
:: 0 = Cleanup can proceed.
::     Application was not running, or this is a noninteractive session.
:: 2 = Interactive session; running application was terminated successfully.
:: 3 = Interactive session; application could not be terminated.
setlocal DisableDelayedExpansion

set "CleanupProcess=%~1"
set "CleanupApplication=%~2"

if not defined CleanupProcess (
    endlocal
    exit /b 3
)
if not defined CleanupApplication (
    set "CleanupApplication=%~1"
)
tasklist.exe /FI "IMAGENAME eq %CleanupProcess%" 2>nul | find /I "%CleanupProcess%" >nul
if errorlevel 1 (
    endlocal
    exit /b 0
)
if defined TBOK_NONINTERACTIVE (
    endlocal
    call :LOG NOTICE: %~2 is running. Noninteractive mode will not terminate it; unlocked cache files will still be cleaned.
    exit /b 0
)
call :LOG Closing %~2 before cache cleanup...
taskkill.exe /F /IM "%~1" >nul 2>&1
set "TaskKillRC=%ERRORLEVEL%"
if not "%TaskKillRC%"=="0" (
    endlocal
    call :LOG WARNING: %~2 could not be closed. Cleanup will continue and remove only files that are not locked.
    exit /b 3
)
endlocal
call :LOG %~2 was closed successfully.
exit /b 2

:BeardSweeper
call :LOG BeardSweeper performs aggressive system, application, and disk cleanup.
call :LOG Running applications are terminated only during interactive cleanup.
call :LOG Noninteractive cleanup preserves application processes and Windows rollback installation files.
cls
	call :LOG  Beard Sweeper, TBOK automagic disk cleanup script!
	call :LOG  	Version 10-27-2026 mm/dd/yyyy
	ECHO.
	ECHO __/\\\\\\\\\\\\\\\__/\\\\\\\\\\\\\_________/\\\\\_______/\\\________/\\\_        
	ECHO  _\///////\\\/////__\/\\\/////////\\\_____/\\\///\\\____\/\\\_____/\\\//__       
	ECHO   _______\/\\\_______\/\\\_______\/\\\___/\\\/__\///\\\__\/\\\__/\\\//_____      
	ECHO    _______\/\\\_______\/\\\\\\\\\\\\\\___/\\\______\//\\\_\/\\\\\\//\\\_____     
	ECHO     _______\/\\\_______\/\\\/////////\\\_\/\\\_______\/\\\_\/\\\//_\//\\\____    
	ECHO      _______\/\\\_______\/\\\_______\/\\\_\//\\\______/\\\__\/\\\____\//\\\___   
	ECHO       _______\/\\\_______\/\\\_______\/\\\__\///\\\__/\\\____\/\\\_____\//\\\__  
	ECHO        _______\/\\\_______\/\\\\\\\\\\\\\/_____\///\\\\\/_____\/\\\______\//\\\_ 
	ECHO         _______\///________\/////////////_________\/////_______\///________\///__  
    ECHO.                                    
	ECHO.	Community effort can be tracked at https://github.com/TheBeardofKnowledge/Scripts-from-my-videos
	ECHO.	Purpose of this batch file is to recover as much "safe" free space from your windows system drive
	ECHO.	to gain back free space that Windows, other programs, and users have consumed.
	ECHO. 	Credits: Because the work we do in I.T. is often unrecognized, this section will show anyone
	ECHO. 	who contributes to the script to improve it - Thank you to all that have helped and tested.
	ECHO. 	TheBeardofKnowledge https://thebeardofknowledge.bio.link/
	ECHO. 	Credit...RayneDance.. https://github.com/RayneDance For improving chrome-edge profile handling
	ECHO. 	Credit...WebFoundUs.. https://tiktok.com/webb_found_us For the Name "Beard Sweeper"
	ECHO.	Credit...tristanghanks..https://github.com/tristanghanks for catching and fixing all typo errors
	ECHO.
:StartofScript
call :LOG *********************************************************************
call :LOG Current system drive space:

set "TBOK_DISK_FREE_BEFORE="
set "TBOK_DISK_TOTAL="

for /f "tokens=1,2 delims=|" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$d=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID='''+$env:SystemDrive+'''');if($d -and $d.Size -gt 0){[Console]::WriteLine([string]$d.FreeSpace+'|'+[string]$d.Size)}" 2^>nul') do (
    set "TBOK_DISK_FREE_BEFORE=%%A"
    set "TBOK_DISK_TOTAL=%%B"
)

if defined TBOK_DISK_FREE_BEFORE (
    for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$f=[double]$env:TBOK_DISK_FREE_BEFORE;$t=[double]$env:TBOK_DISK_TOTAL;'{0:N2} GB free of {1:N2} GB ({2:N1}%% free)' -f ($f/1GB),($t/1GB),(100*$f/$t)"') do (
        call :LOG %%A
    )
) else (
    call :LOG WARNING: Starting free disk space could not be determined.
)

call :LOG *********************************************************************
	ECHO.
	ECHO Initializing Sweeping Procedure...
	ECHO.
	ECHO Starting cleanup of orphaned Windows App installers
c:\windows\system32\rundll32.exe AppxDeploymentClient.dll,AppxCleanupOrphanPackages


:BadPrintJobs
	ECHO Deleting unreleased erroneous print jobs
	NET STOP /Y Spooler >nul 2>&1
	DEL /S /Q /F %systemroot%\system32\spool\printers\*.* >nul 2>&1
	net start spooler >nul 2>&1
	
:fontcache
	ECHO Clearing all Windows Font Cache
	Net stop fontcache >nul 2>&1
	DEL /S /Q /F %systemroot%\ServiceProfiles\LocalService\AppData\Local\FontCache\*.* >nul 2>&1
	NET start fontcache	>nul 2>&1

:WindowsUpdatesCleanup
	ECHO Performing Windows Updates Cleanup
	net stop bits >nul 2>&1
	net stop wuauserv >nul 2>&1
	net stop appidsvc >nul 2>&1
	net stop cryptsvc >nul 2>&1
	ECHO Clearing Windows Update Cache
	DEL /S /Q /F "%ALLUSERSPROFILE%\Application Data\Microsoft\Network\Downloader\*.*"	>nul 2>&1
	rmdir /S /Q "%systemroot%\SoftwareDistribution" >nul 2>&1
	rmdir /S /Q "%systemroot%\system32\catroot2" >nul 2>&1
::commented out the below line because rolling back updates is needed, and it's usually only 1-2Gb.  
::If you don't care about rolling back updates (DANGER Will Robinson), remove the :: in front of the next line.	
::rmdir /S /Q "%systemroot%\Installer\$PatchCache$"  >nul 2>&1
	DEL /S /Q /F "%systemroot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs\*.*" >nul 2>&1
	ECHO Cleanup Complete - Starting Windows Update Services
	net start bits >nul 2>&1
	net start wuauserv >nul 2>&1
	net start appidsvc >nul 2>&1
	net start cryptsvc >nul 2>&1
::for extra aggressive Windows Image cleanup uncomment the next line by removing the :: but keep in mind you won't be able to revert this cleanup
	::DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase

:WindowsTempFilesCleanup
	ECHO Deleting all System temporary files
	DEL /S /Q /F "%systemroot%\Temp\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Prefetch\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\LiveKernelReports\*.dmp"	>nul 2>&1
	DEL /S /Q /F "%systemroot%\appcompat\backuptest\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\System32\sru\*.dat" >nul 2>&1

:WindowsLogs
	ECHO Cleaning Windows Log Files
	DEL /S /Q /F "%systemroot%\Logs\NetSetup\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\SIH\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\CBS\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\DPX\*.log" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\DISM\*.log" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\MeasuredBoot\*.log" >nul 2>&1
	DEL /S /Q /F "%systemroot%\SoftwareDistribution\DataStore\Logs\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\runSW.log" >nul 2>&1
	DEL /S /Q /F "%systemroot%\system32\sru\*.log" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\WindowsUpdate\*.*" >nul 2>&1
	DEL /S /Q /F "%systemroot%\Logs\*.LOG" >nul 2>&1
	DEL /S /Q /F "%systemdrive%\ProgramData\USOshared\Logs\User\*.*" >nul 2>&1

:UserProfileCleanup
	ECHO Cleaning up user profiles
	setlocal enableextensions
	For /d %%u in (c:\users\*) do (
	DEL /S /Q /F "%%u\Local Settings\Temp\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Temp\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Microsoft\Explorer\ThumbCacheToDelete\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\CrashDumps\*.*" 	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\LocalLow\Microsoft\CryptnetUrlCache\Content\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\Teams\Service Worker\CacheStorage\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Microsoft\explorer\thumbcache\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Microsoft\Terminal Server Client\Cache\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Microsoft\Office\16.0\OfficeFileCache\*.*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\PowerPoint\*.tmp" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\Word\*.*" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\Excel\*.*" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState\Recordings\*.*" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Local\Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState\Snips\*.*" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\OneNote\16.0\cache\*.*" >nul 2>&1
	DEL /S /Q /F "%%u\AppData\Roaming\Microsoft\Windows\WebCache\*.*" >nul 2>&1
	)

:TheRecycleBinIsNotAfolder
	ECHO Emptying the recycle bin... you weren't ACTUALLY storing stuff in there, were you? I hope not.
	rd /s /q %systemdrive%\$Recycle.bin	>nul 2>&1

:UserProgramsCacheCleanup
	Echo Cleaning up cache from programs that are space hogs

:iTunesANDiOSbackups
	ECHO Clearing iTunes cached installers, iOS device firmware cache for all users
	call :PrepareApplicationForCleanup "itunes.exe" "Apple iTunes"
	set "ITunesPrepareRC=!ERRORLEVEL!"
	RD /S /Q "%systemdrive%\ProgramData\Apple Inc\Installer Cache"	>nul 2>&1
	RD /S /Q "%systemdrive%\ProgramData\Apple Computer\Installer Cache"	>nul 2>&1
	For /d %%u in (c:\users\*) do (
	RD /S /Q "%%u\AppData\roaming\Apple Computer\iTunes\iPhone Software Updates"	>nul 2>&1
	RD /S /Q "%%u\AppData\roaming\Apple Computer\iTunes\iPod Software Updates"	>nul 2>&1
	)
	ECHO iOS device backup cleanup
if defined TBOK_NONINTERACTIVE (
    call :LOG Noninteractive cleanup: iTunes mobile-device backups will be preserved.
    goto :FreakenMicrosoftTeams
)
ECHO Do you wish to also delete existing iTunes mobile-device backups? [Y/N] Default is Y
CHOICE /C YN /N /T 10 /D Y

IF ERRORLEVEL 2 GOTO :FreakenMicrosoftTeams
IF ERRORLEVEL 1 GOTO :iOSbackups

:iOSbackups
	For /d %%u in (c:\users\*) do (
	RD /S /Q "%%u\AppData\roaming\Apple Computer\MobileSync\Backup"	>nul 2>&1
	RD /S /Q "%%u\Apple\MobileSync\Backup" >nul 2>&1
	)

:FreakenMicrosoftTeams
	ECHO Clearing Microsoft Teams Cache for all users
	call :PrepareApplicationForCleanup "teams.exe" "Microsoft Teams Classic"
	set "TeamsClassicPrepareRC=!ERRORLEVEL!"
	call :PrepareApplicationForCleanup "ms-teams.exe" "Microsoft Teams"
	set "TeamsPrepareRC=!ERRORLEVEL!"
	For /d %%u in (c:\users\*) do (
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\blob_storage\*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\cache\*"		>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\databases\*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\gpucache\*"		>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\indexeddb\*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\Local Storage\*"	>nul 2>&1
	DEL /S /Q /F "%%u\AppData\roaming\microsoft\teams\tmp\*"		>nul 2>&1
	)

:OutlookCache
	ECHO Clearing Outlook Cache
	call :PrepareApplicationForCleanup "outlook.exe" "Microsoft Outlook"
	set "OutlookPrepareRC=!ERRORLEVEL!"
	For /d %%u in (c:\users\*) do (
	RD /S /Q "%%u\AppData\Local\Microsoft\Outlook\RoamCache\"	 >nul 2>&1
	RD /S /Q "%%u\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook\"	 >nul 2>&1
	)

:OneDrive
ECHO Cleaning OneDrive Cache for all users
	call :PrepareApplicationForCleanup "OneDrive.exe" "Microsoft OneDrive"
	set "OneDrivePrepareRC=!ERRORLEVEL!"
	call :PrepareApplicationForCleanup "FileCoAuth.exe" "Microsoft Office File Co-Authoring"
	set "FileCoAuthPrepareRC=!ERRORLEVEL!"
    SETLOCAL EnableDelayedExpansion

    ECHO Cleaning Cache files for all users
    For /d %%u in ("%systemdrive%\users\*") do (
        SET "oneDriveDataDir=%%u\AppData\Local\Microsoft\OneDrive"
        del /q /s /f "!oneDriveDataDir!\logs\*.*" >nul 2>&1
        del /q /s /f "!oneDriveDataDir!\temp\*.*" >nul 2>&1
        del /q /s /f "!oneDriveDataDir!\update\*.*" >nul 2>&1
        del /q /s /f "!oneDriveDataDir!\syncengine\*.*" >nul 2>&1
        del /q /s /f "!oneDriveDataDir!\Telemetry\*.*" >nul 2>&1
        del /q /s /f "%%u\AppData\Local\OneDrive\Cache\qmlcache\*.*" >nul 2>&1
    )

    ECHO Cleaning System OneDrive temporary files
		del /q /s /f "%SystemRoot%\Temp\OneDrive*.*" >nul 2>&1
		del /q /s /f "%ProgramData%\Microsoft OneDrive\*.*" >nul 2>&1
		del /q /s /f "%SystemRoot%\SysWOW64\config\systemprofile\AppData\Local\Microsoft\OneDrive\*.*" >nul 2>&1
		del /q /s /f "%SystemRoot%\System32\config\systemprofile\AppData\Local\Microsoft\OneDrive\*.*" >nul 2>&1
		del /q /s /f "%SystemRoot%\System32\config\systemprofile\AppData\Local\Microsoft\OneDrive\Cache\qmlcache\*.*" >nul 2>&1
		del /q /s /f "%SystemRoot%\SysWOW64\config\systemprofile\AppData\Local\Microsoft\OneDrive\Cache\qmlcache\*.*" >nul 2>&1

    ENDLOCAL
	Echo DONE - Remember to reopen OneDrive to resume file sync.

:WindowsSearchreset
	ECHO Stopping the Search Service to clear and reset it
	sc config wsearch start=disabled >nul 2>&1
	sc stop wsearch >nul 2>&1
	timeout /t 5 /nobreak >nul 2>&1
	::flagging the search database as dirty so it can perform a reindex on next startup
	REG ADD "HKLM\SOFTWARE\Microsoft\Windows Search" /v SetupCompletedSuccessfully /t REG_DWORD /d 0 /f >nul 2>&1
	::clearing out the existing search database
	DEL /S /Q /F /A "%systemdrive%\ProgramData\Microsoft\Search\Data\Applications\Windows\*.*"  >nul 2>&1
	::restoring Search service defaults
	sc config wsearch start=delayed-auto  >nul 2>&1
	::sc start wsearch
	ECHO Windows Search Successfully Reset - search results will be limited while it rebuilds

:WebBrowsers
if defined TBOK_NONINTERACTIVE (
    call :LOG Starting noninteractive browser cache cleanup.
    call :LOG Running browsers will not be terminated; unlocked cache files will still be removed.
) else (
    call :LOG Starting interactive browser cache cleanup.
    call :LOG Running Chrome, Edge, and Firefox processes will be closed before their caches are cleaned.
)

:InternetExploder
call :LOG Cleaning legacy Internet cache for all users...

%SystemRoot%\System32\rundll32.exe InetCpl.cpl,ClearMyTracksByProcess 255 >nul 2>&1
%SystemRoot%\System32\rundll32.exe InetCpl.cpl,ClearMyTracksByProcess 4351 >nul 2>&1

for /d %%U in ("%SystemDrive%\Users\*") do (
    del /s /q /f "%%~fU\AppData\Local\Microsoft\Windows\INetCache\*" >nul 2>&1
    del /s /q /f "%%~fU\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" >nul 2>&1
)

call :LOG Legacy Internet cache cleanup completed.

:GoogleChrome
call :LOG Cleaning Google Chrome cache for all users and profiles
call :PrepareApplicationForCleanup "chrome.exe" "Google Chrome"
set "ChromePrepareRC=!ERRORLEVEL!"

setlocal EnableDelayedExpansion

for /d %%U in ("%SystemDrive%\Users\*") do (
    set "ChromeDataDir=%%~fU\AppData\Local\Google\Chrome\User Data"

    if exist "!ChromeDataDir!" (
        for /d %%P in ("!ChromeDataDir!\Default" "!ChromeDataDir!\Profile *") do (
            if exist "%%~fP" (
                del /q /s /f "%%~fP\Cache\Cache_Data\*" >nul 2>&1
                del /q /s /f "%%~fP\Code Cache\js\*" >nul 2>&1
                del /q /s /f "%%~fP\Code Cache\wasm\*" >nul 2>&1
                del /q /s /f "%%~fP\Service Worker\CacheStorage\*" >nul 2>&1
                del /q /s /f "%%~fP\Service Worker\ScriptCache\*" >nul 2>&1
                del /q /s /f "%%~fP\GPUCache\*" >nul 2>&1
            )
        )
        del /q /s /f "!ChromeDataDir!\System Profile\Cache\Cache_Data\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\System Profile\Code Cache\js\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\System Profile\Code Cache\wasm\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\extensions_crx_cache\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\component_crx_cache\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\GrShaderCache\*" >nul 2>&1
        del /q /s /f "!ChromeDataDir!\ShaderCache\*" >nul 2>&1
    )
)
endlocal

if "!ChromePrepareRC!"=="3" (
    call :LOG NOTICE: Google Chrome remained open. Locked cache files may not have been removed.
)
call :LOG Google Chrome cache cleanup completed.


:EdgeCacheCleanup
call :PrepareApplicationForCleanup "msedge.exe" "Microsoft Edge"
set "EdgePrepareRC=!ERRORLEVEL!"

call :LOG Cleaning Microsoft Edge cache for all users and profiles...

setlocal EnableExtensions EnableDelayedExpansion

for /d %%U in ("%SystemDrive%\Users\*") do (
    set "EdgeDataDir=%%~fU\AppData\Local\Microsoft\Edge\User Data"

    if exist "!EdgeDataDir!\" (
        for /d %%P in ("!EdgeDataDir!\Default" "!EdgeDataDir!\Profile *") do (
            if exist "%%~fP\" (
                del /q /s /f "%%~fP\Cache\Cache_Data\*" >nul 2>&1
                del /q /s /f "%%~fP\Code Cache\js\*" >nul 2>&1
                del /q /s /f "%%~fP\Code Cache\wasm\*" >nul 2>&1
                del /q /s /f "%%~fP\Service Worker\CacheStorage\*" >nul 2>&1
                del /q /s /f "%%~fP\Service Worker\ScriptCache\*" >nul 2>&1
                del /q /s /f "%%~fP\GPUCache\*" >nul 2>&1
                del /q /s /f "%%~fP\EdgeCoupons\coupons_data.db\*.ldb" >nul 2>&1
                del /q /s /f "%%~fP\Media Cache\*" >nul 2>&1
                del /q /s /f "%%~fP\Crashpad\*" >nul 2>&1
                del /q /s /f "%%~fP\OptimizationGuidePredictionModels\*" >nul 2>&1
            )
        )
        del /q /s /f "!EdgeDataDir!\extensions_crx_cache\*" >nul 2>&1
        del /q /s /f "!EdgeDataDir!\BrowserMetrics\*" >nul 2>&1
        del /q /f "!EdgeDataDir!\*.pma" >nul 2>&1
        del /q /s /f "!EdgeDataDir!\component_crx_cache\*" >nul 2>&1
        del /q /s /f "!EdgeDataDir!\GrShaderCache\*" >nul 2>&1
        del /q /s /f "!EdgeDataDir!\ShaderCache\*" >nul 2>&1
    )
)
endlocal
if "!EdgePrepareRC!"=="3" (
    call :LOG NOTICE: Microsoft Edge remained open. Locked cache files may not have been removed.
)
call :LOG Microsoft Edge cache cleanup completed.


:FirefoxCacheCleanup
call :PrepareApplicationForCleanup "firefox.exe" "Mozilla Firefox"
set "FirefoxPrepareRC=!ERRORLEVEL!"

call :LOG Cleaning Mozilla Firefox cache for all users and profiles...

for /d %%U in ("%SystemDrive%\Users\*") do (
    for /d %%P in ("%%~fU\AppData\Local\Mozilla\Firefox\Profiles\*") do (
        if exist "%%~fP\cache2\entries\" (
            del /q /s /f "%%~fP\cache2\entries\*" >nul 2>&1
        )
        if exist "%%~fP\startupCache\" (
            del /q /s /f "%%~fP\startupCache\*" >nul 2>&1
        )
    )
)
if "!FirefoxPrepareRC!"=="3" (
    call :LOG NOTICE: Mozilla Firefox remained open. Locked cache files may not have been removed.
)
call :LOG Mozilla Firefox cache cleanup completed.

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
call :LOG CleanMgr timeout is 30 minutes.

powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$p=Start-Process -FilePath cleanmgr.exe -ArgumentList '/sagerun:69' -PassThru;try{Wait-Process -Id $p.Id -Timeout 1800 -ErrorAction Stop;exit 0}catch{if(-not $p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue};exit 2}" >nul 2>&1

set "CleanMgrRC=!ERRORLEVEL!"

if "!CleanMgrRC!"=="0" (
    call :LOG Disk Cleanup completed successfully.
) else if "!CleanMgrRC!"=="2" (
    call :LOG WARNING: Disk Cleanup exceeded the 30 minute timeout.
    call :LOG WARNING: CleanMgr was terminated and processing will continue.
) else (
    call :LOG WARNING: Disk Cleanup returned exit code !CleanMgrRC!.
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
if defined TBOK_NONINTERACTIVE (
    call :LOG Noninteractive cleanup: restore-point and previous-Windows-install removal was skipped.
    goto :END
)

:PreviousWindowsInstalls
set "TBOK_PREVIOUS_WINDOWS_FOUND=0"

if exist "%SystemDrive%\Windows.old\" (
    set "TBOK_PREVIOUS_WINDOWS_FOUND=1"
    call :LOG FOUND: %SystemDrive%\Windows.old
)
if exist "%SystemDrive%\$Windows.~BT\" (
    set "TBOK_PREVIOUS_WINDOWS_FOUND=1"
    call :LOG FOUND: %SystemDrive%\$Windows.~BT
)
if exist "%SystemDrive%\$Windows.~WS\" (
    set "TBOK_PREVIOUS_WINDOWS_FOUND=1"
    call :LOG FOUND: %SystemDrive%\$Windows.~WS
)
if "!TBOK_PREVIOUS_WINDOWS_FOUND!"=="0" (
    call :LOG No previous Windows installation folders were found. Cleanup was skipped.
    set "TBOK_PREVIOUS_WINDOWS_FOUND="
    goto :BeardsweeperEND
)
set "TBOK_PREVIOUS_WINDOWS_FOUND="
call :LOG Previous Windows installation files were detected that can be removed.

	ECHO	//////////////////////////////////////////////////////////////////////////////////////
	ECHO	/////  Warning! To Maximize Free Space, Previous Windows installation            /////
	ECHO	/////  Cleanup process is about to begin.  You will NOT be able to               /////
	ECHO	/////  restore your pc to a previous installation if you continue.               /////
	ECHO	//////////////////////////////////////////////////////////////////////////////////////
	ECHO Are you sure you wish to continue? [Y/N] Default is Y
	CHOICE /C YN /N /T 10 /D Y

IF ERRORLEVEL 2 GOTO :BeardsweeperEND
IF ERRORLEVEL 1 GOTO :oldwindowsinstalls

:oldwindowsinstalls
call :LOG Removal of old Windows installations will proceed

:Windows.old
::The obvious Windows.old folder that is visible
	IF exist "%systemDrive%\Windows.old" (
	takeown /F "%systemDrive%\Windows.old" /A /R /D Y >nul 2>&1
	icacls "%systemdrive%\Windows.old" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1
	RD /s /q %systemdrive%\Windows.old >nul 2>&1
	) else goto windowsbt
:Windowsbt
::$Windows.~BT hidden folder
	IF exist "%systemDrive%\$Windows.~BT" (
	takeown /F "%systemDrive%\$Windows.~BT" /A /R /D Y >nul 2>&1
	icacls %systemdrive%\$Windows.~BT\*.* /T /grant administrators:F >nul 2>&1
	RD /s /q %systemDrive%\$Windows.~BT >nul 2>&1
	) else goto Windowsws
:Windowsws
::$Windows.~WS hidden folder
IF exist "%systemdrive%\$Windows.~WS" (
	takeown /F "%systemDrive%\$Windows.~WS" /A /R /D Y >nul 2>&1
	icacls %systemdrive%\$Windows.~WS\*.* /T /grant administrators:F >nul 2>&1
	RD /s /q %systemDrive%\$Windows.~WS >nul 2>&1
	) else (
	ECHO No previous windows version folders found
	)
	
:removeRestorePoints
::commended out due to triggerring some antivirus programs, if you want to include this, remove the "::"
::vssadmin delete shadows /all >nul 2>&1 
::Remove the "::" if you want the system to create a new restore point.
::wmic.exe /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "AfterDiskCleanup", 100, 7 >nul 2>&1

:BeardsweeperEND
call :LOG *********************************************************************
call :LOG BeardSweeper disk-space results:

set "TBOK_DISK_FREE_AFTER="

for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$d=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID='''+$env:SystemDrive+'''');if($d){[Console]::WriteLine([string]$d.FreeSpace)}" 2^>nul') do (
    set "TBOK_DISK_FREE_AFTER=%%A"
)
if defined TBOK_DISK_FREE_BEFORE if defined TBOK_DISK_FREE_AFTER if defined TBOK_DISK_TOTAL (
    for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$before=[double]$env:TBOK_DISK_FREE_BEFORE;$after=[double]$env:TBOK_DISK_FREE_AFTER;$total=[double]$env:TBOK_DISK_TOTAL;$saved=$after-$before;$pct=if($total -gt 0){100*$saved/$total}else{0};'Space Recovered: {0:N2} GB ({1:N2}%% of system drive)' -f ($saved/1GB),$pct"') do (
        call :LOG %%A
    )
    for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$f=[double]$env:TBOK_DISK_FREE_AFTER;$t=[double]$env:TBOK_DISK_TOTAL;'{0:N2} GB now free of {1:N2} GB ({2:N1}%% free)' -f ($f/1GB),($t/1GB),(100*$f/$t)"') do (
        call :LOG %%A
    )
) else (
    call :LOG WARNING: BeardSweeper disk-space savings could not be calculated.
)
call :LOG *********************************************************************

set "TBOK_DISK_FREE_BEFORE="
set "TBOK_DISK_FREE_AFTER="
set "TBOK_DISK_TOTAL="
ECHO.

ECHO All cleaned up, have a nice day!
:endmusic
powershell -NoProfile -Command "$player = New-Object System.Media.SoundPlayer \"$env:windir\Media\windows logon.wav\"; $player.PlaySync()"
call :LOG BeardSweeper cleanup completed successfully.
exit /b 0

:Finished
call :LOG ***********************ALL FINISHED!***********************
call :LOG .
call :LOG .              IF THIS SCRIPT HELPED YOU OUT
call :LOG .               CONSIDER BUYING ME A COFFEE
call :LOG .          "https://buymeacoffee.com/thebeardofl"
call :LOG .
call :LOG ***********************ALL FINISHED!***********************

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

choice.exe /c RME /n /m "Restart now, Menu, or Exit? [R/M/E]: Default E in 30 seconds " /t 30 /d E 2>>"%LOGFILE%"
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
call :Delay 10
endlocal
exit /b 0
