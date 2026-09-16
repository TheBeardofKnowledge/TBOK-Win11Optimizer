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
:: 

::turn off echoing all commands
@ECHO OFF
::change the terminal color to something friendlier
color f0

::enable holding variables during script,explicitely enable command extensions, disable variable expansions
setlocal EnableExtensions DisableDelayedExpansion

::Script release version and release date 
:ScriptVersion
set "VERSION=1.6.2"
set "VERDATE=09-16-2026"

:: Automatically check for and obtain administrative elevation, retain working directory, allow special characters in path names
echo No changes are being made at this time.

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not errorlevel 1 goto :GotPrivileges

echo Requesting administrative elevation...
set "ELEVATE_SCRIPT=%~f0"
set "ELEVATE_WORKDIR=%~dp0"

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try { $arguments = '/d /c \"\"' + $env:ELEVATE_SCRIPT + '\"\"'; Start-Process -FilePath $env:ComSpec -Verb RunAs -WorkingDirectory $env:ELEVATE_WORKDIR -ArgumentList $arguments -ErrorAction Stop; exit 0 } catch { exit 1 }"

set "ELEVATE_RC=%ERRORLEVEL%"
set "ELEVATE_SCRIPT="
set "ELEVATE_WORKDIR="

if not "%ELEVATE_RC%"=="0" (
    echo Elevation was canceled or failed.
	echo This script requires elevation in order to check for and adjust system settings and registry
	echo Please retry... the script will now exit
    pause
    exit /b 1
)

exit /b 0

:GotPrivileges
ECHO Script elevated successfully
cls

::::::::::::begin script helper objects::::::::::
::These are items that are called later in the script to perform a function - trims the code size for repeat items
::enable extended script logic and delayed expansion
setlocal enableextensions EnableDelayedExpansion

:LogFile
::Log stored in current script directory with computername, date, time stamped info for multi-pc deployments or multi-run
set "TBOK_TIMESTAMP="
for /f "delims=" %%A in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd-HHmmss"') do (
    set "TBOK_TIMESTAMP=%%A"
)
if not defined TBOK_TIMESTAMP (
    set "TBOK_TIMESTAMP=%RANDOM%-%RANDOM%"
)
set "LOGFILE=%~dp0TBOKwinOptimizer-%COMPUTERNAME%-!TBOK_TIMESTAMP!.log"

:: Fallback registry backups are created only if restore-point creation fails.
set "TBOK_RESTORE_POINT_FAILED=0"
set "TBOK_PROFILE_BACKUP_DIR="

:: Initialize the consolidated service startup queue.
set "TBOK_SERVICE_PLAN=%TEMP%\TBOK-ServicePlan-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

if exist "%TBOK_SERVICE_PLAN%" (
    del /q "%TBOK_SERVICE_PLAN%" >nul 2>&1
)
:: Initialize the consolidated scheduled-task queue.
set "TBOK_TASK_PLAN=%TEMP%\TBOK-TaskPlan-%COMPUTERNAME%-%RANDOM%-%RANDOM%.txt"

if exist "%TBOK_TASK_PLAN%" (
    del /q "%TBOK_TASK_PLAN%" >nul 2>&1
)
goto :MENU

:PrepareRollbackProtection
:restorepoint
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

for /f "tokens=3" %%A in ('reg.exe query "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency 2^>nul ^| findstr /I "SystemRestorePointCreationFrequency"') do (
    set "RestoreFrequencyExisted=1"
    set "RestoreFrequencyValue=%%A"
)
reg.exe add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
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
call :LOG WARNING: Could not create a restore point.

call :LOG Collecting restore-point diagnostics...
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$diagnosticFailure = $false;" ^
    "Write-Output 'System Restore diagnostics:';" ^
    "try {" ^
    "    $config = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop;" ^
    "    $config | Format-List *;" ^
    "} catch {" ^
    "    Write-Output ('WARNING: SystemRestoreConfig query failed: ' + $_.Exception.Message);" ^
    "    $diagnosticFailure = $true;" ^
    "};" ^
    "Write-Output 'Existing restore points:';" ^
    "try {" ^
    "    $points = @(Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -First 5 SequenceNumber,Description,CreationTime);" ^
    "    if ($points.Count -eq 0) {" ^
    "        Write-Output 'No existing restore points were returned.';" ^
    "    } else {" ^
    "        $points | Format-Table -AutoSize;" ^
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
    "if ($diagnosticFailure) { exit 1 } else { exit 0 }" >>"%LOGFILE%" 2>&1

set "RestoreDiagRC=!ERRORLEVEL!"

if not "!RestoreDiagRC!"=="0" (
    call :LOG WARNING: One or more restore-point diagnostic queries failed. Review the preceding log output.
) else (
    call :LOG Restore-point diagnostics completed successfully.
)
call :LOG Creating HKLM and HKCU registry exports as a fallback...

set "HKLMBackupRC=1"
set "HKCUBackupRC=1"

if defined TBOK_PROFILE_BACKUP_DIR (
    reg.exe export HKLM ^
        "!TBOK_PROFILE_BACKUP_DIR!\HKLM-Before-TBOK.reg" /y >>"%LOGFILE%" 2>&1

    set "HKLMBackupRC=!ERRORLEVEL!"

    reg.exe export HKCU ^
        "!TBOK_PROFILE_BACKUP_DIR!\HKCU-ExecutionAccount-Before-TBOK.reg" /y >>"%LOGFILE%" 2>&1

    set "HKCUBackupRC=!ERRORLEVEL!"
) else (
    call :LOG CRITICAL: HKLM and HKCU registry exports were skipped because the fallback backup directory is unavailable.
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

if not "!HKLMBackupRC!!HKCUBackupRC!"=="00" (
    call :LOG CRITICAL: Restore-point creation failed and one or more registry exports also failed.
    call :LOG You may not have a complete method to restore the previous settings.
) else (
    call :LOG Registry fallback exports completed successfully.
)

:RestoreProtectionComplete
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
    "            Write-Output ('DUPLICATE: ' + $service.DisplayName + ' [' + $service.Name + '] -> ' + $requestedMode);" ^
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
	"			};" ^
    "            if ($currentMode -eq $requestedMode) {" ^
    "                Write-Output ('ALREADY CONFIGURED: ' + $service.DisplayName + ' [' + $service.Name + '] -> ' + $requestedMode);" ^
    "                $configured[$key] = $requestedMode;" ^
    "                $alreadyConfiguredCount++;" ^
    "                continue;" ^
    "            };" ^
    "            Write-Output ('CHANGING: ' + $service.DisplayName + ' [' + $service.Name + '] ' + $currentMode + ' -> ' + $requestedMode);" ^
    "            $scOutput = @(& sc.exe config $service.Name start= $requestedMode 2>&1);" ^
    "            $scRC = $LASTEXITCODE;" ^
    "            $scOutput | ForEach-Object { Write-Output ('  ' + $_) };" ^
    "            if ($scRC -eq 0) {" ^
    "                Write-Output ('CHANGED: ' + $service.DisplayName + ' [' + $service.Name + '] ' + $currentMode + ' -> ' + $requestedMode);" ^
    "                $configured[$key] = $requestedMode;" ^
    "                $changedCount++;" ^
    "            } else {" ^
    "                Write-Output ('FAILED: ' + $service.DisplayName + ' [' + $service.Name + '] ' + $currentMode + ' -> ' + $requestedMode + '; Exit code: ' + $scRC);" ^
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

::Helper for for Appx package removal
::Removes installed Appx packages matching a package name pattern.
::Usage: call :RemoveAppxPattern "PackagePattern" "Friendly description"
::Return codes:
::0 = No current-account match, or all-user removal succeeded
::1 = Query or removal failed
::2 = All-user enumeration failed and current-account fallback was used
::3 = Invalid argument

:RemoveAppxPattern
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
    "$pattern = $env:TBOK_APPX_PATTERN;" ^
    "$label = $env:TBOK_APPX_LABEL;" ^
    "try {" ^
    "    $currentPackages = @(Get-AppxPackage -Name $pattern -ErrorAction Stop);" ^
    "} catch {" ^
    "    Write-Output ('ERROR: Current-account package query failed for ' + $label + ': ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "};" ^
    "if ($currentPackages.Count -eq 0) {" ^
    "    Write-Output ('SKIPPED: No installed ' + $label + ' package was found for the current execution account.');" ^
    "    Write-Output 'NOTICE: Other user profiles were not enumerated.';" ^
    "    exit 0;" ^
    "};" ^
    "$allUsersAvailable = $true;" ^
    "try {" ^
    "    $packages = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Stop);" ^
    "} catch {" ^
    "    $allUsersAvailable = $false;" ^
    "    $packages = $currentPackages;" ^
    "    Write-Output ('WARNING: All-user enumeration failed: ' + $_.Exception.Message);" ^
    "    Write-Output 'Falling back to the current execution account.';" ^
    "};" ^
    "$successCount = 0;" ^
    "$failureCount = 0;" ^
    "foreach ($package in $packages) {" ^
    "    try {" ^
    "        Write-Output ('Removing installed package: ' + $package.PackageFullName);" ^
    "        if ($allUsersAvailable) {" ^
    "            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop;" ^
    "        } else {" ^
    "            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop;" ^
    "        };" ^
    "        Write-Output ('SUCCESS: Removed installed package: ' + $package.PackageFullName);" ^
    "        $successCount++;" ^
    "    } catch {" ^
    "        Write-Output ('ERROR: Failed to remove ' + $package.PackageFullName + ': ' + $_.Exception.Message);" ^
    "        $failureCount++;" ^
    "    };" ^
    "};" ^
    "Write-Output ('Successful removals: ' + $successCount);" ^
    "Write-Output ('Failed removals: ' + $failureCount);" ^
    "if ($failureCount -gt 0) {" ^
    "    exit 1;" ^
    "} elseif (-not $allUsersAvailable) {" ^
    "    exit 2;" ^
    "} else {" ^
    "    exit 0;" ^
    "}" >>"%LOGFILE%" 2>&1

set "AppxRC=%ERRORLEVEL%"
endlocal & exit /b %AppxRC%

:: Restore the original SystemRestorePointCreationFrequency value.
:RestorePointFrequency
setlocal DisableDelayedExpansion

if "%RestoreFrequencyExisted%"=="1" (
    reg.exe add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
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

reg.exe delete "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" ^
    /v SystemRestorePointCreationFrequency /f >>"%LOGFILE%" 2>&1

if errorlevel 1 (
    endlocal
    call :LOG WARNING: Could not remove the temporary SystemRestorePointCreationFrequency override.
    exit /b 1
)

endlocal
call :LOG Removed the temporary SystemRestorePointCreationFrequency override.
exit /b 0

:: Capture a Windows memory snapshot and write it to the console and logfile.
:: Usage:
:: call :CaptureMemorySnapshot "BEFORE"
:: call :CaptureMemorySnapshot "AFTER"

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
    "    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop;" ^
    "    $memory = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop;" ^
    "    $processes = @(Get-Process -ErrorAction SilentlyContinue);" ^
    "    $svchost = @($processes | Where-Object { $_.ProcessName -eq 'svchost' });" ^
    "    $totalInstalledBytes = [double]$computer.TotalPhysicalMemory;" ^
    "    $totalVisibleBytes = [double]$os.TotalVisibleMemorySize * 1KB;" ^
    "    $availableBytes = [double]$memory.AvailableBytes;" ^
    "    $usedVisibleBytes = $totalVisibleBytes - $availableBytes;" ^
    "    $hardwareReservedBytes = $totalInstalledBytes - $totalVisibleBytes;" ^
    "    if ($hardwareReservedBytes -lt 0) { $hardwareReservedBytes = 0 };" ^
    "    $committedBytes = [double]$memory.CommittedBytes;" ^
    "    $commitLimitBytes = [double]$memory.CommitLimit;" ^
    "    $physicalUsedPercent = 0;" ^
    "    $commitUsedPercent = 0;" ^
    "    if ($totalVisibleBytes -gt 0) {" ^
    "        $physicalUsedPercent = ($usedVisibleBytes / $totalVisibleBytes) * 100;" ^
    "    };" ^
    "    if ($commitLimitBytes -gt 0) {" ^
    "        $commitUsedPercent = ($committedBytes / $commitLimitBytes) * 100;" ^
    "    };" ^
    "    $svchostWorkingSet = ($svchost | Measure-Object -Property WorkingSet64 -Sum).Sum;" ^
    "    $svchostPrivate = ($svchost | Measure-Object -Property PrivateMemorySize64 -Sum).Sum;" ^
    "    if ($null -eq $svchostWorkingSet) { $svchostWorkingSet = 0 };" ^
    "    if ($null -eq $svchostPrivate) { $svchostPrivate = 0 };" ^
    "    $compressionProcess = Get-Process -Name 'Memory Compression' -ErrorAction SilentlyContinue;" ^
    "    $compressionWorkingSet = 0;" ^
    "    if ($null -ne $compressionProcess) {" ^
    "        $compressionWorkingSet = ($compressionProcess | Measure-Object -Property WorkingSet64 -Sum).Sum;" ^
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

:: Helper for Chassis type detection to avoid enabling desktop tweaks on a device with a battery
:: Returns Laptop, Desktop, or Unknown in CHASSISTYPE
:GetChassisType
set "CHASSISTYPE=Unknown"
for /f "delims=" %%G in ('powershell.exe -NoProfile -Command "$ct=@((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes); if($null -ne ($ct -as [array])){if($ct -match '^(8|9|10|11|12|14|18|21|30|31|32)$'){'Laptop'}elseif($ct -match '^(3|4|5|6|7|13|15|16|24|35|36)$'){'Desktop'}else{'Unknown'}}else{'Unknown'}" 2^>nul') do set "CHASSISTYPE=%%G"
exit /b

::LOG and echo helper to avoid duplicate lines in script - Echoes on screen and also into logfile
::usage call :LOG "message to echo"
:LOG
setlocal DisableDelayedExpansion
set "LogMessage=%*"
echo(%LogMessage%
>>"%LOGFILE%" echo([%DATE% %TIME%] %LogMessage%
endlocal
exit /b 0

::::::::::::end script helper objects::::::::::

:MENU
TITLE TBOK Windows Performance Optimizer Version %version% %verdate%
::MAKE SOUND rundll32.exe cmdext.dll,MessageBeepStub
ECHO                  THE BEARD OF KNOWLEDGE
ECHO ============================================================
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
CHOICE /c 1234 /n /m "Enter 1-4: (Default: 1 in 10 seconds): " /t 10 /d 1
if errorlevel 5 goto :EXIT
if errorlevel 4 goto :WinGet
if errorlevel 3 goto :GamingTweaks
if errorlevel 2 goto :BeardSweeper
if errorlevel 1 goto :SystemTweaks

:SYSTEMTWEAKS
ECHO Creating Log file and adding system information
call :LOG Detected:

ver >>"%LOGFILE%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" >>"%LOGFILE%" 2>&1

powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object Vendor, Name, IdentifyingNumber" ^
    >>"%LOGFILE%" 2>&1

call :LOG Capturing baseline memory usage before modifications...
call :CaptureMemorySnapshot "BEFORE SYSTEM AND USER OPTIMIZATIONS"

::call the restorepoint creation and registry export helper to ensure you can roll back the changes if needed.
call :PrepareRollbackProtection

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
call :LOG Detecting chassis type set by manufacturer
call :GetChassisType

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
call :LOG Optimizing windows virtual memory settings to prevent system hangs
call :LOG This helps on low memory conditions due to SwapFile expansion delay
:: On low ram systems <16GB - Windows keeps the auto mode current allocation too low IMO
:: This can cause system lag-hang conditions while it expands the swap file because it filled up too soon
:: Tests have found that a minimum of 4096 or prefered 8192 is an optimal start - and max size should be double that up to a point
:: If your system has more than >=32GB of ram - just leave it on auto - Windows does a good job at that size or higher

powershell -NoProfile -Command ^
"try { ^
    $ramMB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 0); ^
    Write-Output ('Detected RAM: ' + $ramMB + ' MB'); ^
    if ($ramMB -ge 32768) { ^
        Set-CimInstance -Query 'SELECT * FROM Win32_ComputerSystem' -Property @{AutomaticManagedPageFile=$true} ^| Out-Null; ^
        Write-Output 'Configured Windows automatic pagefile management.'; ^
        exit 0; ^
    }; ^
    $min = [uint32]4096; ^
    switch ($ramMB) { ^
        {$_ -lt 8192} { $max = [uint32]8192; break }; ^
        {$_ -lt 16384} { $max = [uint32]16384; break }; ^
        default { $max = [uint32]24576 } ^
    }; ^
    Set-CimInstance -Query 'SELECT * FROM Win32_ComputerSystem' -Property @{AutomaticManagedPageFile=$false} ^| Out-Null; ^
    $pf = Get-CimInstance Win32_PageFileSetting -Filter 'Name=''C:\\pagefile.sys'''; ^
    if ($pf) { ^
        if (($pf.InitialSize -eq $min) -and ($pf.MaximumSize -eq $max)) { ^
            Write-Output ('Already configured. Min=' + $min + ' MB Max=' + $max + ' MB'); ^
            exit 0; ^
        }; ^
        Set-CimInstance -InputObject $pf -Property @{InitialSize=$min; MaximumSize=$max} ^| Out-Null; ^
    } else { ^
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys'; InitialSize=$min; MaximumSize=$max} ^| Out-Null; ^
    }; ^
    Write-Output ('Configured pagefile: Initial=' + $min + ' MB Maximum=' + $max + ' MB'); ^
    Write-Output 'Reboot required for changes to take effect.'; ^
    exit 0; ^
} catch { ^
    Write-Error $_.Exception.Message; ^
    exit 1; ^
}" >>"%LOGFILE%" 2>&1
set "PageFileRC=!ERRORLEVEL!"

if "!PageFileRC!"=="0" (
    call :LOG Virtual-memory configuration completed successfully.
) else (
    call :LOG ERROR: Virtual-memory configuration failed with exit code !PageFileRC!.
)
ECHO.	
:SERVICES
call :LOG Enable Modern SvHost split process grouping behaviour according to currently installed RAM
call :LOG This changes the svhost process grouping to an optimized state based on installed RAM
call :LOG Works up to around 4TB of RAM - after that theres no noticeable improvement
::This changes how many processes are grouped according to available memory - it does not actually reduce running processes
	set "MemoryKB="

for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$total = (Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Measure-Object Capacity -Sum).Sum; if ($total) { $total / 1KB }" 2^>nul`) do (
    set "MemoryKB=%%A"
)

if not defined MemoryKB (
    call :LOG WARNING: Unable to determine installed RAM. SvcHostSplitThresholdInKB was not changed.
) else (
    call :LOG Installed RAM: !MemoryKB! KB
	set /a "SvcHostThresholdKB=MemoryKB+262144"
	reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v SvcHostSplitThresholdInKB /t REG_DWORD /d !SvcHostThresholdKB! /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :LOG ERROR: Failed to configure SvcHostSplitThresholdInKB.
    ) else (
        call :LOG SvcHostSplitThresholdInKB configured successfully.
    )
)
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

call :LOG Setting sysmain service mode based on RAM and System Disk type
::sysmain was developed to have the system load commonly used items from mechanical drives
::sysmain runs on second boot after install and uses about 70-mb ram as a constant process 
::they load into memory for faster processing with less wait
::with the current speed of NVME drives - the sysmain services is practically irrelevant
::Findings - sysmain should be disabled on systems with < 12GB ram
::However - it benefits mechanical hard drive systems with > 12Gb RAM
::Storage behind a RAID controller sometimes does not report media or bus type information
::For RAID storage I leave the sysmain service on demand mode as a precaution.
::using logic to properly detect what would work better for this specific system is the best approach
:: Get installed memory in GB
set "MemoryGB="
set "DriveType=UNKNOWN"
set "DriveDetectError="
set "DriveDetectFile="

for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$total = (Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Measure-Object Capacity -Sum).Sum; if ($total) { '{0:F0}' -f ($total / 1GB) }" 2^>nul`) do (
    set "MemoryGB=%%A"
)

if not defined MemoryGB (
    call :LOG WARNING: Unable to determine installed memory. Leaving SysMain unchanged.
    goto :DriveDetectionCleanup
)

call :LOG Memory: !MemoryGB! GB

::Detect whether the Windows system drive is an HDD or SSD 
::For RAID volumes this script leave the sysmain service state unchanged
::This is because I couldnt find a reliable method of detection since some raid controllers hide all info
:: Detect the physical media type of the Windows system drive.
set "DriveType=UNKNOWN"
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
    "        if ($null -ne $physicalDisk.SpindleSpeed -and [uint64]$physicalDisk.SpindleSpeed -gt 0) {" ^
    "            $isRotational = $true;" ^
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
    goto :DriveDetectionCleanup
)
for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"RESULT=" "%DriveDetectFile%" 2^>nul') do (
    set "DriveType=%%B"
)
if /i not "!DriveType!"=="HDD" if /i not "!DriveType!"=="SSD" (
    set "DriveType=UNKNOWN"
)
:DriveDetectionCleanup
if defined DriveDetectFile (
    if exist "%DriveDetectFile%" (
        del /q "%DriveDetectFile%" >nul 2>&1
    )
)
call :LOG System Drive Type: !DriveType!

if /i "!DriveType!"=="HDD" (
    if !MemoryGB! GEQ 12 (
        call :LOG Rotational HDD with >=12GB RAM detected.
        call :LOG Setting SysMain to start on demand...
        call :SetServiceStartup SysMain demand
    ) else (
        call :LOG Rotational HDD with <12GB RAM detected.
        call :LOG Disabling SysMain...
        call :SetServiceStartup SysMain disabled
    )
) else if /i "!DriveType!"=="SSD" (
    call :LOG Non-rotational storage detected, including SSD or NVMe.
    call :LOG Disabling SysMain...
    call :SetServiceStartup SysMain disabled
) else (
    call :LOG Unable to determine drive type. Leaving SysMain unchanged.
	call :LOG If you have 12GB of RAM OR MORE but SSD behind a RAID you can manually disable the sysmain service
)
ECHO.
call :LOG Done with services to disable
ECHO.

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
call :SetServiceStartup IKEEXT demand
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
call :SetServiceStartup SessionEnv demand
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
call :SetServiceStartup UmRdpService demand
::ignored call :SetServiceStartup UnistoreSvc_* demand
::ignored call :SetServiceStartup UserDataSvc_* demand
::omitforENTERPRISE call :SetServiceStartup UsoSvc demand
call :SetServiceStartup upnphost demand
call :SetServiceStartup VacSvc demand
call :SetServiceStartup vds demand
call :SetServiceStartup vmicguestinterface demand
call :SetServiceStartup vmicheartbeat demand
call :SetServiceStartup vmickvpexchange demand
call :SetServiceStartup vmicrdv demand
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
call :SetServiceStartup WinRM demand
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
call :LOG **********************************************************
call :LOG        Enabling System-wide Registry Improvements        
call :LOG **********************************************************
call :LOG 

call :LOG Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f  >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Speed up shutdown time
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 5000 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 5000 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enabling long file system path support -why is this disabled by default Microsoft
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling the setting allowing hardware to install whatever software addon - LG Monitor McAffee Incident
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" /v PreventDeviceMetadataFromNetwork /t REG_DWORD /d 1 /f  >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable Webview dependency for Search - breaks nothing - puts search back into classic mode
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledState /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledStateOptions /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v Variant /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayload /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayloadKind  /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledState /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledStateOptions /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v Variant /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayload /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayloadKind  /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Turning off telemetry data collection Local Machine
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

::Control OOBE experience for new users or major updates-testing needed to confirm but it is documented
call :LOG Disable privacy settings experience at first OOBE logon
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v SkipMachineOOBE /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisableVoice /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v Protectyourpc /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v HideEULAPage /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable the lock screen which includes personalized ads - MS Spotlight ads- Default 0
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f	 >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Fix Network Data Usage Graph not working
::Fixes it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\Ndu" /v Start /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Fixes it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

:systemtelemetry
call :LOG Disabling Windows System Telemetry through
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications  /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy  /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled  /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable Powershell telemetry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

:EdgeTweaks
call :LOG Disabling MS Edge Automatic Background Startup
call :LOG Disable Edge so-called start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable MS Edge from running in the background after close
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable MS Edge exhaustive Edge first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling MS Edge submit user feedback
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling MS Edge shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enabling MS Edge PC gaming mode for lower CPU usage while Gaming
::While this serves to lower CPU resource usage for the browser - it also monitors everything running
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable MS Edge Sending Browser Usage DiagnosticData 0
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v DiagnosticData /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling Microsoft Recall from being enabled
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Optional:Enable verbose logon-off status on screen 
call :LOG replaces windows starting and shutting down messages with what its actually doing
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v VerboseStatus /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

::call :LOG Wi-Fi Sense Disable affects devices autoconnecting - leaving enabled
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::call :LOG Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::call :LOG Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has a known vulnerability
::Microsoft protected these keys from being modified in an update
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::Optional For system hardening only - Clear pagefile at shutdown
:: sometimes slows shutdown time removing sensitive memory remnants from pagefile.sys - rebuilds each boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::call :LOG Disable GameDVR - not recommended on AMD X3d chips due to CCD cache routing
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::Disable Windows Code Integrity app control - SmartAPPControl
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

:DEBLOAT
call :LOG System level registry tweaks completed
ECHO.
ECHO.
call :LOG **********************************************************
call :LOG               Time for some bloat removal                
call :LOG **********************************************************
ECHO.
call :LOG Remove and Disable Windows Co-pilot -standard version -NOT M365 copilot- machine wide
::Enable reg key that allows app to be disabled or uninstalled systemwide
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set...
call :LOG Removing existing Microsoft Co-Pilot installed package
call :RemoveAppxPattern "*Microsoft.Copilot*" "Microsoft Copilot"
set "AppxRC=!ERRORLEVEL!"

if "!AppxRC!"=="1" (
    call :LOG WARNING: Installed Microsoft Copilot removal failed.
) else if "!AppxRC!"=="2" (
	call :LOG NOTICE: Current-account fallback processing completed for Microsoft Copilot because all-user enumeration was unavailable.
) else if "!AppxRC!"=="3" (
    call :LOG ERROR: RemoveAppxPattern was called incorrectly for Microsoft Copilot.
)
call :LOG Removing Provisioned-package for Microsoft CoPilot
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $packages = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -Like '*Microsoft.Copilot*');" ^
    "    if ($packages.Count -eq 0) {" ^
    "        Write-Output 'No provisioned Microsoft.Copilot packages found.';" ^
    "        exit 0;" ^
    "    };" ^
    "    foreach ($package in $packages) {" ^
    "        Write-Output ('Removing provisioned package: ' + $package.DisplayName);" ^
    "        $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null;" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG WARNING: One or more provisioned Copilot packages could not be removed.
)

call :LOG Configuring registry keys to prevent reinstallation through future updates. NOT M365 Copilot.
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v CopilotDisabledReason /t REG_SZ /d "IsEnabledForGeographicRegionFailed" /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}" /t REG_SZ /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" /v IsUserEligible /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...


call :LOG Removing Bing Search
call :LOG Removing installed Microsoft Bing Search packages...
call :RemoveAppxPattern "*Microsoft.BingSearch*" "Microsoft Bing Search"
set "AppxRC=!ERRORLEVEL!"

if "!AppxRC!"=="1" (
    call :LOG WARNING: One or more installed Microsoft Bing Search packages could not be removed.
) else if "!AppxRC!"=="2" (
    call :LOG NOTICE: Current-account fallback processing completed for Microsoft Bing Search because all-user enumeration was unavailable.
) else if "!AppxRC!"=="3" (
    call :LOG ERROR: RemoveAppxPattern was called incorrectly for Microsoft Bing Search.
)

call :LOG Removing provisioned-package for Microsoft BingSearch...
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $packages = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -Like '*Microsoft.BingSearch*');" ^
    "    if ($packages.Count -eq 0) {" ^
    "        Write-Output 'SKIPPED: No provisioned Microsoft Bing Search packages found.';" ^
    "        exit 0;" ^
    "    };" ^
    "    foreach ($package in $packages) {" ^
    "        Write-Output ('Removing provisioned package: ' + $package.DisplayName);" ^
    "        $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null;" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG WARNING: One or more provisioned BingSearch packages could not be removed.
)

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
call :RemoveAppxPattern "Microsoft.WidgetsPlatformRuntime" "Microsoft Widgets Platform Runtime"
set "AppxRC=!ERRORLEVEL!"

if "!AppxRC!"=="1" (
    call :LOG WARNING: Installed Microsoft Widgets Platform Runtime removal failed.
) else if "!AppxRC!"=="2" (
 call :LOG NOTICE: Current-account fallback processing completed for Microsoft Widgets Platform Runtime because all-user enumeration was unavailable.
) else if "!AppxRC!"=="3" (
    call :LOG ERROR: RemoveAppxPattern was called incorrectly for Microsoft Widgets Platform Runtime.
)

call :LOG Removing provisioned-package Microsoft Widgets...
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $packages = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -Like '*Microsoft.WidgetsPlatformRuntime*');" ^
    "    if ($packages.Count -eq 0) {" ^
    "        Write-Output 'SKIPPED: No provisioned Microsoft Widgets Platform Runtime packages found.';" ^
    "        exit 0;" ^
    "    };" ^
    "    foreach ($package in $packages) {" ^
    "        Write-Output ('Removing provisioned package: ' + $package.DisplayName);" ^
    "        $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null;" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

if errorlevel 1 (
    call :LOG WARNING: One or more provisioned Microsoft.WidgetsPlatformRuntime packages could not be removed.
)

call :LOG Removing provisioned Microsoft WebExperience packages...
call :RemoveAppxPattern "MicrosoftWindows.Client.WebExperience" "Windows Web Experience"
set "AppxRC=!ERRORLEVEL!"

if "!AppxRC!"=="1" (
    call :LOG WARNING: Installed Windows Web Experience removal failed.
) else if "!AppxRC!"=="2" (
	call :LOG NOTICE: Current-account fallback processing completed for Windows Web Experience because all-user enumeration was unavailable.
) else if "!AppxRC!"=="3" (
    call :LOG ERROR: RemoveAppxPattern was called incorrectly for Windows Web Experience.
)
call :LOG Removing provisioned-package WebExperience
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {" ^
    "    $packages = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -Like '*MicrosoftWindows.Client.WebExperience*');" ^
    "    if ($packages.Count -eq 0) {" ^
    "        Write-Output 'SKIPPED: No provisioned Windows Web Experience packages found.';" ^
    "        exit 0;" ^
    "    };" ^
    "    foreach ($package in $packages) {" ^
    "        Write-Output ('Removing provisioned package: ' + $package.DisplayName);" ^
    "        $package | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null;" ^
    "    };" ^
    "    exit 0;" ^
    "} catch {" ^
    "    Write-Output ('ERROR: ' + $_.Exception.Message);" ^
    "    exit 1;" ^
    "}" >>"%LOGFILE%" 2>&1

if errorlevel 1 (
    call :LOG WARNING: One or more provisioned MicrosoftWindows.Client.WebExperience packages could not be removed.
)
:: ___________________________________________PENDING SECTION START___________________________________________

::optional LMS AMT-vPro Environment disable
::call :LOG Disable LMS1 AKA Intel vPro system
::Stopping and disabling service: LMS
::powershell -NoProfile -Command "$svc = Get-Service LMS -ErrorAction SilentlyContinue; if($svc){  Stop-Service LMS -Force -ErrorAction SilentlyContinue;  Set-Service LMS -StartupType Disabled }"
::Removing service: LMS
::Remove LMS driver packages
::Remove driver package: lms.inf_amd64_3e015d10576493ca
::Remove driver package: lms.inf
::Search for and delete LMS executable files
::No LMS.exe files found in Program Files directories.

::___________________________________________PENDING SECTION END___________________________________________

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

:WindowsTasks
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
call :PrepareRollbackProtection
goto UserRegistryDeployment
:: ===============================================================
:: -START SECTION - APPLY PER USER REGISTRY SETTINGS TO ALL USERS
:: ===============================================================
:: PER USER REGISTRY KEYS TO APPLY - This section applies registry tweaks
:: This will loop through each existing user account on the pc and apply the registry settings below 
:: %base%\ is normally HKCU\
:: REG ADD "%BASE%\Path" /v ValueName /t REG_DWORD /d 1 /f
::example
::REG ADD "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >nul 2>&1
:: if errorlevel 1 call :Log ERROR setting ValueName for %BASE%

::call the restorepoint creation and registry export helper to ensure you can roll back the changes if needed.

:ApplySettings

call :LOG ========= Apply Tweaks to User Registry Hives and Default ==============

call :LOG DEBUG ApplySettings called. Arg1=[%~1]
set "BASE=%~1"
if not defined BASE (
    call :LOG ERROR ApplySettings called with no registry hive
    goto :eof
)
call :LOG *****************************************************************
call :LOG Applying User Registry settings to %BASE%
call :LOG *****************************************************************
::***********************************************USER HKCU REGISTRY KEYS*******************************************

call :LOG Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
reg query "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" >nul 2>&1
if errorlevel 1 (
    call :LOG Registry key already absent: Bags
) else (
    reg delete "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :LOG ERROR: Failed to delete Explorer Bags registry key.
    ) else (
        call :LOG Deleted Explorer Bags registry key.
    )
)
reg query "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" >nul 2>&1

if errorlevel 1 (
    call :LOG Registry key already absent: BagMRU
) else (
    reg delete "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f >>"%LOGFILE%" 2>&1

    if errorlevel 1 (
        call :LOG ERROR: Failed to delete Explorer BagMRU registry key.
    ) else (
        call :LOG Deleted Explorer BagMRU registry key.
    )
)
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /v FolderType /t REG_SZ /d NotSpecified /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Preference- Default Explorer to open at "This PC" as default instead of the quick menu
::--1 - fastest load --2 is default quick access - and 3 is downloads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling allowing Windows apps to run in the background systemwide
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enabling Game Mode always on which helps further reduce background system resource usage
::uses ~14mb ram but helps Processors with CCD technology and e-core parking
REG ADD "%BASE%\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Preference -Enabling end task from Taskbar - super useful to avoid opening task manager just to end a stalled app
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Preference -Enabling show full right-click context menus in Windows 11
REG ADD "%BASE%\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling bing search in start menu -keep the start menu local
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enable allow Pinning more apps on the start menu for less wasted space -such a big start menu
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Setting speed up menu show delay - Windows default is 400ms - why wait so long
REG ADD "%BASE%\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 10 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling some gaudi resource consuming desktop visual effects -explorer
call :LOG Setting visual effects setting to custom
:: 3 is custom - default 0 - 1 best appearance - 2 best performance but takes windows look to 1990
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disable taskbar animations
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::copilot icon in taskbar
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAI /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Disable alpha blending selection
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::disable shadows
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Disable the people icon on the taskbar
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Disable Taskbar widgets icon -not uninstall - thats done later in the script
reg.exe add "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >nul 2>&1
set "TaskbarDaRC=!ERRORLEVEL!"
if not "!TaskbarDaRC!"=="0" (
    call :LOG WARNING: Could not set TaskbarDa for %BASE%. Exit code: !TaskbarDaRC!.
) else (
    call :LOG TaskbarDa disabled for %BASE%.
)
::Enable dragging full windows instead of just the frame
REG ADD "%BASE%\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Set the minimum animation speed to 0 for disable
REG ADD "%BASE%\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Disable keyboard input delay
REG ADD "%BASE%\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Disable Windows Aero Peek
REG ADD "%BASE%\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::Optional Preference Taskbar StartMenu alignment left
::REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f

::call :LOG Disable transparency effects - optional - left enabled for WindHawk TransparentTB and WallpaperEngine
::REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f 

::research this - possible webview dependency removal - found all over the place - runaway webview2.exe processes
::REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v WebView /t REG_DWORD /d 0 /f

:advertising
call :LOG Start Disabling User level ads in Windows

call :LOG Disable Explorer search box suggestions -Ads-
REG ADD "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling file explorer ads
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable reocurring finish setup ads named "Suggest ways to get the most out of Windows"
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling lock screen tips and ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling personalized ads
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling welcome experience ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling settings ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling auto install of suggested apps - "Get more out of windows" ad space
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling general tips and ads - why are these together Microslop
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling home screen ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling Timeline Suggestions ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable Windows Content Delivery
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v ContentDeliveryAllowed /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable automatic enabling of OEM and Preinstalled apps
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEverEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

::Windows Diagnostics Feedback request frequency
REG ADD "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG DELETE "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /f >>"%LOGFILE%" 2>&1
reg.exe query "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds >nul 2>&1

if errorlevel 1 (
    call :LOG Registry value already absent: PeriodInNanoSeconds
) else (
    reg.exe delete "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /f >>"%LOGFILE%" 2>&1

    if errorlevel 1 (
        call :LOG ERROR: Failed to delete PeriodInNanoSeconds.
    ) else (
        call :LOG Deleted PeriodInNanoSeconds.
    )
)
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableTailoredExperiencesWithDiagnosticData  /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" /v EnthusiastMode /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG disable windows feeds for users
::WindowsPro, Enterprise, LTSC
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
:: Windows Home and legacy Feeds taskbar preference.
reg.exe add "%BASE%\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f >nul 2>&1
set "ShellFeedsRC=!ERRORLEVEL!"
if not "!ShellFeedsRC!"=="0" (
    call :LOG WARNING: Could not set ShellFeedsTaskbarViewMode for %BASE%. Exit code: !ShellFeedsRC!.
    call :LOG NOTICE: The policy-level Windows Feeds setting was still applied successfully.
) else (
    call :LOG ShellFeedsTaskbarViewMode configured for %BASE%.
)

call :LOG Disabling start menu ads method 2
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling tailored experiences with telemetry
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Preferrence- Disable the TaskView button in the taskbar - same as "Win tab" -clutter
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable the people button in the taskbar
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" /v PeopleBand /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
 
call :LOG Enable right-click menu to auto end tasks from taskbar 
REG ADD "%BASE%\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Hide the meet now button on the taskbar
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v HideSCAMeetNow /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Set the searchbox taskbar to icon only for less wasted space
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling Cross-Device Resume -optional but reverse this if you sync your phone to your pc - honestly your web browser should do this - mostly web
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" /v IsResumeAllowed /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disable MS Co-pilot per user registry settings -standard version - not m365 copilot
REG ADD "%BASE%\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot" /v AllowCopilotRuntime /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG --- Disable Microsoft Office logging
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG --- Disable Microsoft Office client telemetry
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG --- Disable Microsoft Office Customer Experience Improvement Program
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG --- Disable Microsoft Office feedback
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Disabling sticky keys feature because leaving something on the shift-key is just as bad as capslock
REG ADD "%BASE%\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 58 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

::disabled this section because it negatively affects chips with CCD cache routing -X3d etc- and e-core parking when gaming
::add logic to detect if processor has CCD cache before disbling - for now leave as is
::disable game DVR
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_FSEBehavior /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_EFSEFeatureFlags /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...

::Allow RDP remote assistance - leave enabled for business use
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v fAllowToGetHelp /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
goto :eof

::********************************END of USER REGISTRY SETTINGS TO APPLY********************************
:UserRegistryDeployment
call :LOG Starting per-user registry deployment...

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :LOG Processing loaded user hives

for /f "delims=" %%U in ('reg query HKEY_USERS ^| findstr /R /I /C:"^HKEY_USERS\\S-1-5-21-" /C:"^HKEY_USERS\\S-1-12-1-" ^| findstr /V /I "_Classes"') do (
    call :ApplySettings "%%U"
)
:: ================================
:: 2. ALL USER PROFILES
:: ================================
call :Log Processing user profiles (NTUSER.DAT)

for /d %%D in ("%SystemDrive%\Users\*") do (
    set "PROFILE_NAME=%%~nxD"

    :: Skip known system profile directories.
    if /I not "!PROFILE_NAME!"=="Public" if /I not "!PROFILE_NAME!"=="Default" if /I not "!PROFILE_NAME!"=="Default User" (
        if exist "%%D\NTUSER.DAT" (
            if "!TBOK_RESTORE_POINT_FAILED!"=="1" (
                if defined TBOK_PROFILE_BACKUP_DIR (
                    if exist "!TBOK_PROFILE_BACKUP_DIR!" (
                        copy /y "%%D\NTUSER.DAT" ^
                            "!TBOK_PROFILE_BACKUP_DIR!\%%~nxD-NTUSER.DAT" >>"%LOGFILE%" 2>&1

                        if errorlevel 1 (
                            call :LOG NOTICE: NTUSER.DAT for %%D could not be copied. The profile may currently be loaded.
                        ) else (
                            call :LOG Backed up NTUSER.DAT for %%D.
                        )
                    )
                )
            )

            call :LOG Loading hive for %%D

            reg.exe query HKU\TempHive >nul 2>&1
            if not errorlevel 1 (
                call :LOG WARNING: Found a previously mounted TempHive. Attempting cleanup.

                reg.exe unload HKU\TempHive >>"%LOGFILE%" 2>&1
                if errorlevel 1 (
                    call :LOG ERROR: Could not unload the previously mounted TempHive.
                ) else (
                    call :LOG Temporary hive cleanup completed.
                )
            )

            reg.exe load HKU\TempHive "%%D\NTUSER.DAT" >nul 2>&1
            if errorlevel 1 (
                call :LOG Skipping offline load for %%D. The profile hive may already be loaded or currently in use.
            ) else (
                call :ApplySettings "HKU\TempHive"

                reg.exe unload HKU\TempHive >nul 2>&1
                if errorlevel 1 (
                    call :LOG ERROR: Failed to unload temporary hive for %%D.
                ) else (
                    call :LOG Successfully processed unloaded profile %%D.
                )
            )
        ) else (
            call :LOG Skipping profile directory without NTUSER.DAT: %%D
        )
    )
)

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
                call :LOG WARNING: Could not back up the Default profile NTUSER.DAT.
            ) else (
                call :LOG Backed up the Default profile NTUSER.DAT.
            )
        )
    )
)
    reg.exe query HKU\DefaultHive >nul 2>&1

    if not errorlevel 1 (
        call :LOG WARNING: DefaultHive is already mounted. Attempting cleanup.
        reg.exe unload HKU\DefaultHive >>"%LOGFILE%" 2>&1
    )

    reg.exe load HKU\DefaultHive "%SystemDrive%\Users\Default\NTUSER.DAT" >>"%LOGFILE%" 2>&1

    if errorlevel 1 (
        call :LOG ERROR: Failed to load Default profile.
    ) else (
        call :ApplySettings "HKU\DefaultHive"
        reg.exe unload HKU\DefaultHive >>"%LOGFILE%" 2>&1

        if errorlevel 1 (
            call :LOG ERROR: Failed to unload Default profile.
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
call :Log ===== COMPLETE =====
call :LOG Done. Log file: %LOGFILE%

goto REBOOT
::======================================END FOR EACH USER REGISTRY LOOP==========================================

:GamingTweaks
call :LOG **********************************************************
call :LOG        Begin Gaming Improvements        
call :LOG **********************************************************
call :LOG 

::call the restorepoint creation and registry export helper to ensure you can roll back the changes if needed.
call :PrepareRollbackProtection

call :LOG Reset and Redetect Windows HPET dependency -High Precision Event Timer- - fixes issue where HPET was not detected properly
bcdedit.exe /deletevalue useplatformclock >nul 2>&1
if errorlevel 1 (
    call :LOG useplatformclock was not explicitly configured or could not be changed.
) else (
    call :LOG Removed explicit useplatformclock override.
)
call :LOG Enabling HAGS - Hardware Accelerated GPU Scheduling - will only work if supported but at least not disabled
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HWSchMode /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enabling Optimizations for Windowed Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR\Graphics" /v OptimizationsForWindowedGames /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Increasing system responsiveness for Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v SystemResponsiveness /t REG_DWORD /d 0x0000000a /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Setting priority for Windowed Apps and Games based on Microsoft Learn Docs
::Games Multimedia Class Scheduler Service - GPU priority SFIO priority and Affinity are all listed as not yet used
::Scheduling priority High treats Task Priority setting as 2 instead of respecting number 1 low - 8 high
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d Medium /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::The Latency Sensitive value is defaulted to TRUE - this key is here to ensure defaults
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Latency Sensitive" /t REG_SZ /d True /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

::Audio Multimedia Class Scheduler Service
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "GPU Priority" /t REG_DWORD /d 8 /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v Priority /t REG_DWORD /d 6 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Scheduling Category" /t REG_SZ /d Medium /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "SFIO Priority" /t REG_SZ /d High /f >>"%LOGFILE%" 2>&1
::if errorlevel 1 call :LOG ERROR: Failed to set ...
::The Latency Sensitive value is defaulted to TRUE - this key is here to ensure defaults
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio" /v "Latency Sensitive" /t REG_SZ /d True /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

:detectchassisGamingTweaks
call :LOG Detecting chassis type before applying desktop power tweaks
call :GetChassisType

call :LOG Detected chassis category: !CHASSISTYPE!

if /i "!CHASSISTYPE!"=="Laptop" goto laptopgaming
if /i "!CHASSISTYPE!"=="Desktop" goto desktopgaming
goto unknownchassisgaming

:laptopgaming
call :LOG Laptop detected - desktop power tweaks were skipped
goto REBOOT

:desktopgaming
call :LOG Desktop detected - enabling desktop-only optimizations

call :LOG Disabling power throttling
	REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
	REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v NoLazyMode /t REG_DWORD /d 00000000 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...
	REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v AlwaysOn /t REG_DWORD /d 00000000 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 call :LOG ERROR: Failed to set ...

call :LOG Enabling Ultimate Performance power plan for desktops only
call :LOG Creating and activating Ultimate Performance power plan...

set "ULTIMATE_GUID="

for /f "tokens=4" %%G in ('powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2^>nul') do (
    set "ULTIMATE_GUID=%%G"
)

if not defined ULTIMATE_GUID (
    call :LOG WARNING: Could not create the Ultimate Performance power plan.
) else (
    powercfg.exe /setactive !ULTIMATE_GUID! >>"%LOGFILE%" 2>&1

    if errorlevel 1 (
        call :LOG ERROR: Failed to activate Ultimate Performance plan !ULTIMATE_GUID!.
    ) else (
        call :LOG Ultimate Performance plan activated: !ULTIMATE_GUID!
    )
)
::Removed: Disabling the dynamic P-States for GPUS - Testing found that the increase in performance was negligible to nothing
::Greater improvement was found from just a mild overclock instead...will leave in here for use with much older GPUs
::This is because most GPU's from this Decade already agressively handle clock speeds and P-States
::		call :LOG Disabling Dynamic P-state for GPUs...forces gpu to run at maximum performance
::powershell -NoProfile -Command ^
::"$gpuDevices = Get-CimInstance Win32_VideoController | Where-Object {$_.PNPDeviceID -match 'PCI\\VEN_'}; ^
::foreach ($gpu in $gpuDevices) { ^
::    Write-Host ('Processing GPU: ' + $gpu.Name); ^
::    $driverKey = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $gpu.PNPDeviceID) -Name Driver -ErrorAction SilentlyContinue).Driver; ^
::    if ($driverKey) { ^
::        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driverKey; ^
::        if (Test-Path $regPath) { ^
::            Write-Host ('Setting registry key at: ' + $regPath); ^
::            New-ItemProperty -Path $regPath -Name DisableDynamicPstate -PropertyType DWord -Value 1 -Force | Out-Null; ^
::            Write-Host 'Dynamic P-state disabled successfully'; ^
::        } ^
::    } ^
::}"
goto REBOOT

	:unknownchassisgaming
		call :LOG Unable to determine chassis type. Skipped power tweaks.
	goto REBOOT

:BeardSweeper
call :LOG BeardSweeper is Currently In development - will be released soon
goto :menu

:WinGet
call :LOG Installing or Updating to latest version of the WinGet Package manager
powershell.exe -c Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
PowerShell.exe -c Install-Module -Name Microsoft.WinGet.Client -Force
call :LOG Searching for and updating existing installed packages
winget update --all --include-unknown --accept-source-agreements --accept-package-agreements --silent --verbose
goto :menu

:REBOOT
call :LOG ****************************ALL FINISHED!******************************
call :LOG .
call :LOG .    IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE
call :LOG .         "https://buymeacoffee.com/thebeardofl"
call :LOG .
call :LOG ****************************ALL FINISHED!******************************

call :LOG A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
choice /c YN /n /m "Restart now? [Y/N]: Default N in 10 seconds and exit " /t 10 /d N
if errorlevel 2 goto EXIT
if errorlevel 1 goto RESTART

:RESTART
call :LOG Restarting PC.

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
endlocal
shutdown.exe /r /t 0
exit /b 0

:EXIT
call :LOG Script exiting.

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
endlocal
timeout /t 10 /nobreak >nul
exit /b 0
