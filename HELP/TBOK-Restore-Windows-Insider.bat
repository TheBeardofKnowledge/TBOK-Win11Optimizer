@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ============================================================================
REM TBOK Restore Windows Insider - v12
REM Native Batch logging edition.
REM Restores Windows Insider, diagnostic-data, WER, compatibility, feedback,
REM companion services, UI visibility, and Windows Update prerequisites
REM changed or potentially blocked by TBOK.
REM
REM Features in v12:
REM   - Non-blocking UAC elevation (closes initial unprivileged window).
REM   - Accurate AD Domain and Entra ID (Azure AD) detection.
REM   - Automatic deep-clean (/FORCEPUBLICWU /RESETSELFHOST /RESETWU) on
REM     standalone (non-domain) PCs unless /NOAUTO is specified.
REM   - Automatic GPO Override Persistence: If domain Group Policy overwrites
REM     AllowTelemetry during gpupdate, registers a SYSTEM scheduled task
REM     triggered on boot and Group Policy refresh (Event ID 8004) to keep
REM     AllowTelemetry=3, and immediately applies it.
REM
REM Optional modes:
REM   /FORCEPUBLICWU    Remove local WSUS URLs and force update scan sources to WU.
REM   /RESETSELFHOST    Backup and reset local WindowsSelfHost enrollment state.
REM   /RESETWU          Rename Windows Update cache stores so Windows rebuilds them.
REM   /NOAUTO           Disable automatic deep-clean on standalone PCs.
REM   /NOPERSIST        Disable automatic GPO override scheduled task creation.
REM   /REMOVEPERSIST    Remove the TBOK GPO override scheduled task and exit.
REM ============================================================================

fltmc.exe >nul 2>&1
if errorlevel 1 goto :RequestElevation
goto :InsiderRestoreElevated

:RequestElevation
echo Requesting administrative elevation...
set "TBOK_INSIDER_SCRIPT=%~f0"
set "TBOK_INSIDER_ARGS=%*"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -Command ^
    "try { $sp = @{ FilePath = $env:TBOK_INSIDER_SCRIPT; Verb = 'RunAs'; ErrorAction = 'Stop' }; if ($env:TBOK_INSIDER_ARGS) { $sp.ArgumentList = $env:TBOK_INSIDER_ARGS }; Start-Process @sp; exit 0 } catch { exit 1 }"
exit /b %ERRORLEVEL%

:InsiderRestoreElevated

REM ---------------------------------------------------------------------------
REM Parse recovery modes
REM ---------------------------------------------------------------------------
set "FORCE_PUBLIC_WU=0"
set "RESET_SELFHOST=0"
set "RESET_WU=0"
set "NO_AUTO=0"
set "NO_PERSIST=0"
set "REMOVE_PERSIST=0"
set "TBOK_ORIGINAL_ARGS=%*"

:ParseRecoveryArgs
if "%~1"=="" goto :RecoveryArgsParsed
if /I "%~1"=="/FORCEPUBLICWU" set "FORCE_PUBLIC_WU=1"
if /I "%~1"=="/RESETSELFHOST" set "RESET_SELFHOST=1"
if /I "%~1"=="/RESETWU" set "RESET_WU=1"
if /I "%~1"=="/NOAUTO" set "NO_AUTO=1"
if /I "%~1"=="/NOPERSIST" set "NO_PERSIST=1"
if /I "%~1"=="/REMOVEPERSIST" set "REMOVE_PERSIST=1"
shift
goto :ParseRecoveryArgs

:RecoveryArgsParsed

if "%REMOVE_PERSIST%"=="1" (
    echo Removing TBOK-Insider-Telemetry-Persist scheduled task...
    schtasks.exe /Delete /TN "\TBOK-Insider-Telemetry-Persist" /F >nul 2>&1
    if errorlevel 1 (
        echo Task \TBOK-Insider-Telemetry-Persist was not found or could not be removed.
    ) else (
        echo Task \TBOK-Insider-Telemetry-Persist removed successfully.
    )
    pause
    exit /b 0
)

REM ---------------------------------------------------------------------------
REM Create native Batch troubleshooting log beside this script
REM ---------------------------------------------------------------------------
set "TBOK_TIMESTAMP="
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyyMMdd-HHmmss'" 2^>nul`) do set "TBOK_TIMESTAMP=%%A"
if not defined TBOK_TIMESTAMP set "TBOK_TIMESTAMP=UnknownTime"
set "LOGFILE=%~dp0TBOK-Restore-Windows-Insider-%COMPUTERNAME%-%TBOK_TIMESTAMP%.log"

>"%LOGFILE%" echo TBOK Windows Insider Recovery v12 - Troubleshooting Log
>>"%LOGFILE%" echo Started: %DATE% %TIME%
>>"%LOGFILE%" echo Computer: %COMPUTERNAME%
>>"%LOGFILE%" echo User: %USERDOMAIN%\%USERNAME%
>>"%LOGFILE%" echo Script: %~f0
>>"%LOGFILE%" echo Arguments: %TBOK_ORIGINAL_ARGS%
>>"%LOGFILE%" echo.

call :LOG "Troubleshooting log: %LOGFILE%"
call :LOG ""

REM ---------------------------------------------------------------------------
REM Detect Windows & Domain / Entra ID Membership early
REM ---------------------------------------------------------------------------
set "WINDOWS_BUILD="
set "WINDOWS_BUILD_NUM="
set "WINDOWS_PRODUCT="
set "WINDOWS_FAMILY="
set "WINDOWS_DISPLAYVERSION="

for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr.exe /I /C:"CurrentBuildNumber"`) do set "WINDOWS_BUILD=%%A"
for /f "usebackq tokens=2,*" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul ^| findstr.exe /I /C:"ProductName"`) do set "WINDOWS_PRODUCT=%%B"
for /f "usebackq tokens=2,*" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr.exe /I /C:"DisplayVersion"`) do set "WINDOWS_DISPLAYVERSION=%%B"

if not defined WINDOWS_BUILD (
    call :LOG "ERROR: Windows build number could not be determined."
    goto :FailureNoRestart
)
set /a "WINDOWS_BUILD_NUM=%WINDOWS_BUILD%" >nul 2>&1
if errorlevel 1 (
    call :LOG "ERROR: Windows build number is not numeric: %WINDOWS_BUILD%"
    goto :FailureNoRestart
)
if %WINDOWS_BUILD_NUM% GEQ 22000 (set "WINDOWS_FAMILY=Windows 11") else set "WINDOWS_FAMILY=Windows 10"
if not defined WINDOWS_PRODUCT set "WINDOWS_PRODUCT=Unknown edition"
if not defined WINDOWS_DISPLAYVERSION set "WINDOWS_DISPLAYVERSION=Unknown"

set "TBOK_DOMAIN_JOINED=UNKNOWN"
set "TBOK_DOMAIN_NAME="
set "TBOK_ENTRA_JOINED=NO"

for /f "usebackq tokens=1,2 delims=|" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop; $d = if ($cs.PartOfDomain) { 'YES' } else { 'NO' }; Write-Output ($d + '|' + $cs.Domain) } catch { Write-Output 'UNKNOWN|' }" 2^>nul`) do (
    set "TBOK_DOMAIN_JOINED=%%A"
    set "TBOK_DOMAIN_NAME=%%B"
)

dsregcmd.exe /status 2>nul | findstr.exe /I /C:"AzureAdJoined : YES" >nul
if not errorlevel 1 set "TBOK_ENTRA_JOINED=YES"

REM Automatically enable deep recovery flags if PC is NOT part of an AD domain
set "AUTO_STANDALONE_APPLIED=0"
if /I "%TBOK_DOMAIN_JOINED%"=="NO" (
    if "%NO_AUTO%"=="0" (
        set "FORCE_PUBLIC_WU=1"
        set "RESET_SELFHOST=1"
        set "RESET_WU=1"
        set "AUTO_STANDALONE_APPLIED=1"
    )
)

cls
call :LOG "================================================================"
call :LOG "TBOK Windows Insider Program Restore - v12"
call :LOG "================================================================"
call :LOG "OS               : %WINDOWS_FAMILY%"
call :LOG "Edition string   : %WINDOWS_PRODUCT%"
call :LOG "Display version  : %WINDOWS_DISPLAYVERSION%"
call :LOG "Build            : %WINDOWS_BUILD%"
call :LOG "AD Domain Joined : %TBOK_DOMAIN_JOINED% (%TBOK_DOMAIN_NAME%)"
call :LOG "Entra ID Joined  : %TBOK_ENTRA_JOINED%"
call :LOG "Force public WU  : %FORCE_PUBLIC_WU%"
call :LOG "Reset SelfHost   : %RESET_SELFHOST%"
call :LOG "Reset WU cache   : %RESET_WU%"
call :LOG "================================================================"
call :LOG ""
call :LOG "RECOVERY MODES"
call :LOG "----------------------------------------------------------------"
call :LOG "Normal recovery: restores optional diagnostics, enables Preview Builds,"
call :LOG "restores DiagTrack/WU/MSA services, WER, compatibility tasks, and UI access."
call :LOG ""
call :LOG "Auto GPO Override: When domain Group Policy overwrites AllowTelemetry,"
call :LOG "automatically deploys a SYSTEM scheduled task to keep AllowTelemetry=3"
call :LOG "on startup and after every Group Policy refresh (pass /NOPERSIST to skip)."
call :LOG ""
call :LOG "Standalone Auto-Mode: When the PC is not joined to an AD domain,"
call :LOG "/FORCEPUBLICWU, /RESETSELFHOST, and /RESETWU are enabled automatically"
call :LOG "(pass /NOAUTO to disable automatic deep-clean on standalone PCs)."
call :LOG "----------------------------------------------------------------"
call :LOG "SELECTED FOR THIS RUN"
if "%AUTO_STANDALONE_APPLIED%"=="1" call :LOG "  [AUTO] Standalone PC detected: deep-clean modes enabled automatically."
if "%FORCE_PUBLIC_WU%"=="1" (call :LOG "  [ENABLED] Force public Windows Update") else call :LOG "  [OFF] Force public Windows Update"
if "%RESET_SELFHOST%"=="1" (call :LOG "  [ENABLED] Reset WindowsSelfHost") else call :LOG "  [OFF] Reset WindowsSelfHost"
if "%RESET_WU%"=="1" (call :LOG "  [ENABLED] Reset Windows Update caches") else call :LOG "  [OFF] Reset Windows Update caches"
call :LOG "----------------------------------------------------------------"

set "FAILED=0"
set "VERIFY_FAIL=0"
set "FAIL_REASONS="
set "PROFILE_REPAIR_WARNING=0"
set "HOSTS_BLOCK_WARNING=0"
set "HW_GATE_WARNING=0"
set "GPO_OVERRIDE_ACTIVE=0"
set "GPO_PERSIST_DEPLOYED=0"

REM ---------------------------------------------------------------------------
REM Initial diagnostic capture before any repair
REM ---------------------------------------------------------------------------
call :LOG ""
call :LOG "PRE-REPAIR POLICY CHECKPOINT"
call :CapturePolicyCheckpoint "BEFORE_REPAIR"
call :AppendDiagnosticSnapshot "PRE-REPAIR"

REM ---------------------------------------------------------------------------
REM 1 - Diagnostic data, DiagTrack state, and AutoLogger
REM ---------------------------------------------------------------------------
call :LOG ""
call :LOG "[1/8] Restoring optional diagnostic data and DiagTrack AutoLogger..."
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f >>"%LOGFILE%" 2>&1
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v MaxTelemetryAllowed /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"

REM Clear explicit DiagTrack runtime status blocks if set by privacy utilities
reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v DiagTrackStatus /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v UploadPermissionReceived /f >>"%LOGFILE%" 2>&1

reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"

set "DEFAULT_CONTROL_SET="
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SYSTEM\Select" /v Default 2^>nul ^| findstr.exe /I /C:"Default"`) do call :ResolveDefaultControlSet %%A
if defined DEFAULT_CONTROL_SET (
    reg.exe add "HKLM\SYSTEM\%DEFAULT_CONTROL_SET%\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 set "FAILED=1"
) else call :LOG "NOTICE: Default control-set mapping could not be resolved."
call :CapturePolicyCheckpoint "AFTER_REPAIR_WRITE"

REM ---------------------------------------------------------------------------
REM 2 - Preview build, Settings UI visibility, & Windows Update policy
REM ---------------------------------------------------------------------------
call :LOG "[2/8] Restoring preview-build policy controls and Settings UI access..."
if %WINDOWS_BUILD_NUM% LSS 16299 (
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview /t REG_DWORD /d 1 /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 set "FAILED=1"
    reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds /f >>"%LOGFILE%" 2>&1
) else (
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds /t REG_DWORD /d 2 /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 set "FAILED=1"
    reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview /f >>"%LOGFILE%" 2>&1
)
for %%V in (BranchReadinessLevel DeferFeatureUpdates DeferFeatureUpdatesPeriodInDays PauseFeatureUpdatesStartTime TargetReleaseVersion TargetReleaseVersionInfo ProductVersion PauseFeatureUpdates DeferQualityUpdates DeferQualityUpdatesPeriodInDays PauseQualityUpdates PauseQualityUpdatesStartTime SetDisableUXWUAccess SetDisablePauseUXAccess) do reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v %%V /f >>"%LOGFILE%" 2>&1

REM Ensure Windows Insider Settings page is not hidden via SettingsPageVisibility
for /f "usebackq tokens=2,*" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v SettingsPageVisibility 2^>nul ^| findstr.exe /I /C:"SettingsPageVisibility"`) do (
    echo "%%B" | findstr.exe /I "windowsinsider" >nul
    if not errorlevel 1 (
        call :LOG "Removing SettingsPageVisibility policy blocking Windows Insider UI: %%B"
        reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v SettingsPageVisibility /f >>"%LOGFILE%" 2>&1
        if errorlevel 1 set "FAILED=1"
    )
)

call :ReportUpdateSourcePolicy
if "%FORCE_PUBLIC_WU%"=="1" (
    call :ForcePublicWindowsUpdate
    if errorlevel 1 set "FAILED=1"
)
if "%RESET_SELFHOST%"=="1" (
    call :ResetWindowsSelfHost
    if errorlevel 1 set "FAILED=1"
)
if "%RESET_WU%"=="1" (
    call :ResetWindowsUpdateComponents
    if errorlevel 1 set "FAILED=1"
)

REM ---------------------------------------------------------------------------
REM 3 - Core & Companion Services (DiagTrack, WU, BITS, UsoSvc, DoSvc, MSA, Medic)
REM ---------------------------------------------------------------------------
call :LOG "[3/8] Restoring required service availability..."
sc.exe config DiagTrack start= auto >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"
sc.exe start DiagTrack >>"%LOGFILE%" 2>&1

for %%S in (wuauserv BITS UsoSvc DoSvc wlidsvc) do (
    sc.exe qc %%S 2>nul | findstr.exe /I /C:"DISABLED" >nul
    if not errorlevel 1 (
        call :LOG "Re-enabling disabled service: %%S"
        sc.exe config %%S start= demand >>"%LOGFILE%" 2>&1
        if errorlevel 1 set "FAILED=1"
    )
)

REM WaaSMedicSvc is protected against sc.exe config; restore Start=3 via registry if disabled (4)
set "WAAS_START="
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start 2^>nul ^| findstr.exe /I /C:"Start"`) do set "WAAS_START=%%A"
if /I "%WAAS_START%"=="0x4" (
    call :LOG "Re-enabling disabled WaaSMedicSvc via registry..."
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
    if errorlevel 1 set "FAILED=1"
)

REM ---------------------------------------------------------------------------
REM 4 - WER
REM ---------------------------------------------------------------------------
call :LOG "[4/8] Restoring Windows Error Reporting..."
reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled /f >>"%LOGFILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled /f >>"%LOGFILE%" 2>&1
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$c=Get-Command Enable-WindowsErrorReporting -ErrorAction SilentlyContinue;if($null -ne $c){$r=Enable-WindowsErrorReporting -ErrorAction Stop;if($r -eq $false){exit 1}};exit 0}catch{Write-Output $_.Exception.Message;exit 1}" >>"%LOGFILE%" 2>&1
if errorlevel 1 set "FAILED=1"

REM ---------------------------------------------------------------------------
REM 5 - Tasks
REM ---------------------------------------------------------------------------
call :LOG "[5/8] Restoring diagnostic scheduled tasks when present..."
for %%T in ("\Microsoft\Windows\Feedback\Siuf\DmClient" "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" "\Microsoft\Windows\Windows Error Reporting\QueueReporting" "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" "\Microsoft\Windows\Autochk\Proxy") do schtasks.exe /Change /TN %%T /ENABLE >>"%LOGFILE%" 2>&1

REM ---------------------------------------------------------------------------
REM 6 - SIUF user profile settings
REM ---------------------------------------------------------------------------
call :LOG "[6/8] Restoring default Windows feedback-frequency behavior..."
set "TBOK_PROFILE_REPAIR=%TEMP%\TBOK-Insider-ProfileRepair-%RANDOM%-%RANDOM%.txt"
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference='Stop';$failed=0;$changed=0;$skipped=0;function Repair-Hive([string]$root){try{$p='Registry::'+$root+'\SOFTWARE\Microsoft\Siuf\Rules';if(Test-Path -LiteralPath $p){$v=Get-ItemProperty -LiteralPath $p -Name NumberOfSIUFInPeriod -ErrorAction SilentlyContinue;if($null -ne $v){Remove-ItemProperty -LiteralPath $p -Name NumberOfSIUFInPeriod -Force -ErrorAction Stop;$script:changed++}else{$script:skipped++}}else{$script:skipped++}}catch{Write-Output ('ERROR='+$root+': '+$_.Exception.Message);$script:failed++}};$loaded=@(Get-ChildItem Registry::HKEY_USERS -ErrorAction Stop|Where-Object{$_.PSChildName -match '^S-1-(5-21|12-1)-' -and $_.PSChildName -notmatch '_Classes$'});foreach($h in $loaded){Repair-Hive ('HKEY_USERS\'+$h.PSChildName)};$profiles=@(Get-CimInstance Win32_UserProfile -ErrorAction Stop|Where-Object{-not $_.Special -and $_.LocalPath});foreach($p in $profiles){if($p.Loaded){continue};$nt=Join-Path $p.LocalPath 'NTUSER.DAT';if(-not(Test-Path -LiteralPath $nt)){continue};$mount='TBOKInsider_'+([guid]::NewGuid().ToString('N'));$target='HKU\'+$mount;$o=@(& reg.exe load $target $nt 2>&1);if($LASTEXITCODE -ne 0){Write-Output ('ERROR='+$p.LocalPath+': hive load failed');$failed++;continue};try{Repair-Hive ('HKEY_USERS\'+$mount)}finally{[gc]::Collect();[gc]::WaitForPendingFinalizers();$null=& reg.exe unload $target 2>&1;if($LASTEXITCODE -ne 0){Write-Output ('ERROR='+$p.LocalPath+': hive unload failed');$failed++}}};$defaultNt=Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT';if(Test-Path -LiteralPath $defaultNt){$mount='TBOKInsider_Default';$target='HKU\'+$mount;$o=@(& reg.exe load $target $defaultNt 2>&1);if($LASTEXITCODE -eq 0){try{Repair-Hive ('HKEY_USERS\'+$mount)}finally{[gc]::Collect();[gc]::WaitForPendingFinalizers();$null=& reg.exe unload $target 2>&1;if($LASTEXITCODE -ne 0){Write-Output 'ERROR=Default profile: hive unload failed';$failed++}}}else{Write-Output 'ERROR=Default profile: hive load failed';$failed++}};Write-Output ('CHANGED='+$changed);Write-Output ('SKIPPED='+$skipped);Write-Output ('FAILED='+$failed);if($failed -gt 0){exit 1}else{exit 0}" >"%TBOK_PROFILE_REPAIR%" 2>&1
set "PROFILE_REPAIR_RC=%ERRORLEVEL%"
type "%TBOK_PROFILE_REPAIR%"
type "%TBOK_PROFILE_REPAIR%" >>"%LOGFILE%" 2>&1
if exist "%TBOK_PROFILE_REPAIR%" del /q "%TBOK_PROFILE_REPAIR%" >nul 2>&1
if not "%PROFILE_REPAIR_RC%"=="0" set "PROFILE_REPAIR_WARNING=1"

REM ---------------------------------------------------------------------------
REM 7 - Domain-aware policy refresh, auto GPO override, network/hardware gates
REM ---------------------------------------------------------------------------
call :LOG "[7/8] Applying domain-aware policy refresh and auditing network/hardware gates..."
call :LOG "AD Domain Joined: %TBOK_DOMAIN_JOINED%  Domain/Workgroup: %TBOK_DOMAIN_NAME%  Entra ID Joined: %TBOK_ENTRA_JOINED%"

if /I "%TBOK_DOMAIN_JOINED%"=="YES" goto :RunDomainGpupdate
if /I "%TBOK_DOMAIN_JOINED%"=="NO" goto :SkipDomainGpupdate

call :LOG "WARNING: Domain membership could not be determined. gpupdate was skipped to avoid unintended policy reapplication."
set "GPUPDATE_RC=SKIPPED_UNKNOWN"
goto :AfterDomainGpupdate

:RunDomainGpupdate
call :LOG "Domain-joined computer detected. Running gpupdate /target:computer /force..."
gpupdate.exe /target:computer /force >>"%LOGFILE%" 2>&1
set "GPUPDATE_RC=%ERRORLEVEL%"
call :LOG "gpupdate exit code: %GPUPDATE_RC%"
goto :AfterDomainGpupdate

:SkipDomainGpupdate
call :LOG "Computer is not domain joined. gpupdate was intentionally skipped."
set "GPUPDATE_RC=SKIPPED_NOT_DOMAIN_JOINED"

:AfterDomainGpupdate
call :CapturePolicyCheckpoint "AFTER_POLICY_REFRESH_DECISION"

REM Check if Group Policy / MDM re-locked AllowTelemetry after policy refresh
set "POST_GP_TELEMETRY=UNSET"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"`) do set "POST_GP_TELEMETRY=%%A"

if /I not "%POST_GP_TELEMETRY%"=="0x3" (
    set "GPO_OVERRIDE_ACTIVE=1"
    call :LOG "NOTICE: Group Policy overwrote Policy AllowTelemetry to %POST_GP_TELEMETRY%."
    if "%NO_PERSIST%"=="0" (
        call :DeployGpoTelemetryOverrideTask
    ) else (
        call :LOG "NOTICE: /NOPERSIST specified; automatic GPO override task was not created."
    )
)

call :CheckHostsFileBlocks
if %WINDOWS_BUILD_NUM% GEQ 22000 call :CheckWin11HardwareGates
call :ReportManagementState
call :AppendDiagnosticSnapshot "POST-POLICY-REFRESH"

REM ---------------------------------------------------------------------------
REM 8 - Verification
REM ---------------------------------------------------------------------------
call :LOG "[8/8] Verifying restored prerequisites..."
call :RunVerification
if "%VERIFY_FAIL%"=="0" goto :SUCCESS
goto :FAILURE

:SUCCESS
call :LOG ""
call :LOG "RESULT: Windows Insider and related diagnostic settings were restored successfully."
if "%GPO_PERSIST_DEPLOYED%"=="1" (
    call :LOG "NOTICE: Domain Group Policy (%TBOK_DOMAIN_NAME%) actively enforces AllowTelemetry=%POST_GP_TELEMETRY%."
    call :LOG "        Deployed SYSTEM scheduled task '\TBOK-Insider-Telemetry-Persist' to automatically"
    call :LOG "        re-apply AllowTelemetry=3 on startup and after every Group Policy refresh."
    call :LOG "        (Run '%~nx0 /REMOVEPERSIST' at any time to remove this override task.)"
)
if "%HOSTS_BLOCK_WARNING%"=="1" call :LOG "NOTICE: Potential Microsoft domain blocks were detected in the hosts file. Review the log."
if "%HW_GATE_WARNING%"=="1" call :LOG "NOTICE: TPM 2.0 or Secure Boot did not report ready. Windows 11 Insider enrollment may block unsupported hardware."
call :LOG "Troubleshooting log: %LOGFILE%"
call :LOG ""
call :LOG "Next steps:"
call :LOG "  1. Restart Windows."
if %WINDOWS_BUILD_NUM% LSS 22000 (call :LOG "  2. Open Settings > Update & Security > Windows Insider Program.") else call :LOG "  2. Open Settings > Windows Update > Windows Insider Program."
call :LOG "  3. Link an account registered with the Windows Insider Program."
call :LOG "  4. Select an Insider channel currently offered to this device."
call :LOG "  5. Return to Windows Update and select Check for updates."
call :LOG ""
call :LOG "================================================================"
call :LOG "                 RESTART REQUIRED"
call :LOG "================================================================"
call :LOG "Windows must restart before the restored Insider, diagnostic,"
call :LOG "Windows Update, AutoLogger, and enrollment settings can be fully used."
call :LOG "Save all open work before restarting."
call :LOG "================================================================"

"%SystemRoot%\System32\choice.exe" /C YN /N /M "Restart this computer now? [Y/N]: "
set "RESTART_CHOICE_RC=%ERRORLEVEL%"
call :LOG "Restart prompt result code: %RESTART_CHOICE_RC%"
if "%RESTART_CHOICE_RC%"=="1" goto :RestartComputer
if "%RESTART_CHOICE_RC%"=="2" goto :RestartDeclined
call :LOG "WARNING: Unexpected restart prompt result. Windows was not restarted automatically."
goto :RestartDeferred

:RestartDeclined
call :LOG "Restart was declined. Restart Windows manually before evaluating Insider access."
goto :RestartDeferred

:RestartComputer
call :LOG "Restarting Windows in 15 seconds. Save any remaining work now."
shutdown.exe /r /t 15 /d p:2:4 /c "TBOK Windows Insider recovery requires a restart to apply restored settings." >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG "ERROR: Windows could not be scheduled to restart automatically."
    goto :RestartDeferred
)
exit /b 0

:RestartDeferred
call :LOG "Press any key to close this window."
pause >nul
exit /b 0

:FAILURE
call :LOG ""
call :LOG "RESULT: Windows Insider prerequisites are NOT fully restored."
call :LOG "Failed areas: %FAIL_REASONS%"
call :LOG "Troubleshooting log: %LOGFILE%"
call :LOG ""
call :LOG "Possible causes:"
call :LOG "  - Domain Group Policy, Intune/MDM, ConfigMgr, or WSUS reapplied policy."
call :LOG "  - TBOK, another privacy utility, scheduled task, or RMM policy reapplied restrictions."
call :LOG "  - The PC is intentionally managed by policy that does not permit Insider Preview builds."
call :LOG "  - WindowsSelfHost or Windows Update state may require an optional recovery mode."
call :LOG ""
call :LOG "A gpresult computer summary and relevant policy dumps are included in this log."
call :LOG "Press any key to close this window."
pause >nul
exit /b 1

:FailureNoRestart
if defined LOGFILE call :LOG "Troubleshooting log: %LOGFILE%"
echo Press any key to close this window...
pause >nul
exit /b 1

REM ============================================================================
REM Helpers
REM ============================================================================

:LOG
set "TBOK_LOG_TEXT=%~1"
echo(%TBOK_LOG_TEXT%
if defined LOGFILE >>"%LOGFILE%" echo([%DATE% %TIME%] %TBOK_LOG_TEXT%
set "TBOK_LOG_TEXT="
exit /b 0

:DeployGpoTelemetryOverrideTask
call :LOG "Deploying SYSTEM scheduled task to automatically override Group Policy telemetry lock..."
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try { $ErrorActionPreference = 'Stop'; $taskName = 'TBOK-Insider-Telemetry-Persist'; $action = New-ScheduledTaskAction -Execute 'reg.exe' -Argument 'add \"HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection\" /v AllowTelemetry /t REG_DWORD /d 3 /f'; $trigBoot = New-ScheduledTaskTrigger -AtStartup; $cimTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler; $trigGp = New-CimInstance -CimClass $cimTriggerClass -ClientOnly; $trigGp.Enabled = $true; $trigGp.Subscription = '<QueryList><Query Id=\"0\" Path=\"Microsoft-Windows-GroupPolicy/Operational\"><Select Path=\"Microsoft-Windows-GroupPolicy/Operational\">*[System[Provider[@Name=''Microsoft-Windows-GroupPolicy''] and (EventID=8004)]]</Select></Query></QueryList>'; $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew; Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Trigger @($trigBoot, $trigGp) -Principal $principal -Settings $settings -Force | Out-Null; Start-ScheduledTask -TaskName $taskName -TaskPath '\'; Start-Sleep -Seconds 2; exit 0 } catch { Write-Output ('TASK_ERROR: ' + $_.Exception.Message); exit 1 }" >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG "WARNING: Failed to register SYSTEM scheduled task for GPO override. Applying direct registry fallback..."
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 3 /f >>"%LOGFILE%" 2>&1
) else (
    call :LOG "SUCCESS: Registered and executed '\TBOK-Insider-Telemetry-Persist' (triggers: Startup + GroupPolicy Event ID 8004)."
    set "GPO_PERSIST_DEPLOYED=1"
)
exit /b 0

:CapturePolicyCheckpoint
set "CHECKPOINT_NAME=%~1"
set "CHECK_POLICY_TELEMETRY=UNSET"
set "CHECK_LOCAL_TELEMETRY=UNSET"
set "CHECK_MAX_TELEMETRY=UNSET"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"`) do set "CHECK_POLICY_TELEMETRY=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"`) do set "CHECK_LOCAL_TELEMETRY=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v MaxTelemetryAllowed 2^>nul ^| findstr.exe /I /C:"MaxTelemetryAllowed"`) do set "CHECK_MAX_TELEMETRY=%%A"
call :LOG "Policy checkpoint %CHECKPOINT_NAME%: Policy AllowTelemetry=%CHECK_POLICY_TELEMETRY%; Local AllowTelemetry=%CHECK_LOCAL_TELEMETRY%; MaxTelemetryAllowed=%CHECK_MAX_TELEMETRY%"
set "CHECKPOINT_NAME="
set "CHECK_POLICY_TELEMETRY="
set "CHECK_LOCAL_TELEMETRY="
set "CHECK_MAX_TELEMETRY="
exit /b 0

:CheckHostsFileBlocks
set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"
if not exist "%HOSTS_FILE%" exit /b 0
findstr.exe /I /R "^[^#]*[0-9]\.[0-9].*\(vortex\.data\.microsoft\.com\|settings-win\.data\.microsoft\.com\|sls\.update\.microsoft\.com\|fe3\.delivery\.mp\.microsoft\.com\|insideruser\.microsoft\.com\)" "%HOSTS_FILE%" >>"%LOGFILE%" 2>&1
if not errorlevel 1 (
    call :LOG "WARNING: Hosts file contains entries that may block Microsoft telemetry or Insider endpoints."
    set "HOSTS_BLOCK_WARNING=1"
) else (
    call :LOG "Hosts file endpoint audit: PASS (no common Insider/telemetry blocks found)"
)
exit /b 0

:CheckWin11HardwareGates
set "TPM_STATUS=UNKNOWN"
set "SB_STATUS=UNKNOWN"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$t=Get-Tpm -ErrorAction Stop;if($t.TpmPresent -and $t.TpmReady){'READY'}else{'NOT_READY'}}catch{'UNKNOWN'}" 2^>nul`) do set "TPM_STATUS=%%A"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{if(Confirm-SecureBootUEFI -ErrorAction Stop){'ENABLED'}else{'DISABLED'}}catch{'UNSUPPORTED_OR_OFF'}" 2^>nul`) do set "SB_STATUS=%%A"
call :LOG "Windows 11 Hardware Gates: TPM=%TPM_STATUS%; SecureBoot=%SB_STATUS%"
if /I not "%TPM_STATUS%"=="READY" set "HW_GATE_WARNING=1"
if /I not "%SB_STATUS%"=="ENABLED" set "HW_GATE_WARNING=1"
exit /b 0

:AppendDiagnosticSnapshot
set "SNAPSHOT_NAME=%~1"
>>"%LOGFILE%" echo.
>>"%LOGFILE%" echo ================================================================================
>>"%LOGFILE%" echo DIAGNOSTIC SNAPSHOT: %SNAPSHOT_NAME%
>>"%LOGFILE%" echo ================================================================================
>>"%LOGFILE%" echo --- DataCollection policy ---
reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /s >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- CurrentVersion DataCollection ---
reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /s >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- MDM PolicyManager System ---
reg.exe query "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\System" /v AllowTelemetry >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- WindowsUpdate policy ---
reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /s >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- DiagTrack service ---
sc.exe qc DiagTrack >>"%LOGFILE%" 2>&1
sc.exe query DiagTrack >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- Diagtrack-Listener AutoLogger ---
reg.exe query "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /s >>"%LOGFILE%" 2>&1
set "SNAPSHOT_NAME="
exit /b 0

:ReportUpdateSourcePolicy
set "TBOK_WUSERVER="
set "TBOK_USEWUSERVER="
set "TBOK_FEATURE_SOURCE="
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v WUServer 2^>nul ^| findstr.exe /I /C:"WUServer"`) do set "TBOK_WUSERVER=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v UseWUServer 2^>nul ^| findstr.exe /I /C:"UseWUServer"`) do set "TBOK_USEWUSERVER=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetPolicyDrivenUpdateSourceForFeatureUpdates 2^>nul ^| findstr.exe /I /C:"SetPolicyDrivenUpdateSourceForFeatureUpdates"`) do set "TBOK_FEATURE_SOURCE=%%A"
call :LOG "Update source diagnosis: WUServer=%TBOK_WUSERVER%; UseWUServer=%TBOK_USEWUSERVER%; FeatureSource=%TBOK_FEATURE_SOURCE%"
exit /b 0

:ForcePublicWindowsUpdate
call :LOG "[FORCE PUBLIC WU] Removing WSUS/update-source redirection..."
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v UseWUServer /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
if errorlevel 1 exit /b 1
for %%V in (WUServer WUStatusServer UpdateServiceUrl UpdateServiceUrlAlternate DisableDualScan DoNotConnectToWindowsUpdateInternetLocations) do reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v %%V /f >>"%LOGFILE%" 2>&1
for %%V in (SetPolicyDrivenUpdateSourceForFeatureUpdates SetPolicyDrivenUpdateSourceForQualityUpdates SetPolicyDrivenUpdateSourceForDriverUpdates SetPolicyDrivenUpdateSourceForOtherUpdates) do reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v %%V /t REG_DWORD /d 0 /f >>"%LOGFILE%" 2>&1
exit /b 0

:ResetWindowsSelfHost
call :LOG "[RESET SELFHOST] Backing up and resetting local Insider enrollment state..."
set "SELFHOST_BACKUP=%~dp0TBOK-WindowsSelfHost-%COMPUTERNAME%-%TBOK_TIMESTAMP%.reg"
reg.exe query "HKLM\SOFTWARE\Microsoft\WindowsSelfHost" >nul 2>&1
if errorlevel 1 (
    call :LOG "WindowsSelfHost is not present. Nothing to reset."
    exit /b 0
)
reg.exe export "HKLM\SOFTWARE\Microsoft\WindowsSelfHost" "%SELFHOST_BACKUP%" /y >>"%LOGFILE%" 2>&1
if errorlevel 1 (
    call :LOG "ERROR: WindowsSelfHost backup failed. Reset not attempted."
    exit /b 1
)
reg.exe delete "HKLM\SOFTWARE\Microsoft\WindowsSelfHost" /f >>"%LOGFILE%" 2>&1
if errorlevel 1 exit /b 1
call :LOG "WindowsSelfHost backup: %SELFHOST_BACKUP%"
exit /b 0

:ResetWindowsUpdateComponents
call :LOG "[RESET WU] Resetting Windows Update cache components..."
net.exe stop bits /y >>"%LOGFILE%" 2>&1
net.exe stop wuauserv /y >>"%LOGFILE%" 2>&1
net.exe stop cryptsvc /y >>"%LOGFILE%" 2>&1
set "WU_STAMP=%RANDOM%-%RANDOM%"
if exist "%SystemRoot%\SoftwareDistribution" ren "%SystemRoot%\SoftwareDistribution" "SoftwareDistribution.TBOK-%WU_STAMP%" >>"%LOGFILE%" 2>&1
if exist "%SystemRoot%\System32\catroot2" ren "%SystemRoot%\System32\catroot2" "catroot2.TBOK-%WU_STAMP%" >>"%LOGFILE%" 2>&1
net.exe start cryptsvc >>"%LOGFILE%" 2>&1
net.exe start bits >>"%LOGFILE%" 2>&1
net.exe start wuauserv >>"%LOGFILE%" 2>&1
exit /b 0

:ReportManagementState
call :LOG "Device management diagnosis is being written to the troubleshooting log."
>>"%LOGFILE%" echo.
>>"%LOGFILE%" echo --- dsregcmd /status ---
dsregcmd.exe /status >>"%LOGFILE%" 2>&1
>>"%LOGFILE%" echo --- gpresult computer summary ---
gpresult.exe /scope computer /r >>"%LOGFILE%" 2>&1
exit /b 0

:ResolveDefaultControlSet
set "DEFAULT_CONTROL_SET="
set "DEFAULT_CONTROL_SET_NUM="
set "DEFAULT_CONTROL_SET_PADDED="
set /a "DEFAULT_CONTROL_SET_NUM=%~1" >nul 2>&1
if errorlevel 1 exit /b 1
set "DEFAULT_CONTROL_SET_PADDED=00%DEFAULT_CONTROL_SET_NUM%"
call set "DEFAULT_CONTROL_SET=ControlSet%%DEFAULT_CONTROL_SET_PADDED:~-3%%"
set "DEFAULT_CONTROL_SET_PADDED="
exit /b 0

:RunVerification
call :LOG ""
call :LOG "VERIFICATION RESULTS"
call :LOG "----------------------------------------------------------------"
set "LOCAL_TELEMETRY="
set "POLICY_TELEMETRY="
set "PREVIEW="
set "LEGACY_PREVIEW="
set "DIAGTRACK_START="
set "DIAGTRACK_STATE="
set "AUTOLOGGER_START="
set "WER_DISABLED="
set "WER_POLICY_DISABLED="
set "WER_EFFECTIVE=UNKNOWN"
set "WAAS_VERIFY="

for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"`) do set "LOCAL_TELEMETRY=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"`) do set "POLICY_TELEMETRY=%%A"
if %WINDOWS_BUILD_NUM% LSS 16299 (
    for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview 2^>nul ^| findstr.exe /I /C:"AllowBuildPreview"`) do set "LEGACY_PREVIEW=%%A"
) else (
    for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds 2^>nul ^| findstr.exe /I /C:"ManagePreviewBuilds"`) do set "PREVIEW=%%A"
)
for /f "usebackq tokens=4" %%A in (`sc.exe qc DiagTrack 2^>nul ^| findstr.exe /I /C:"START_TYPE"`) do set "DIAGTRACK_START=%%A"
for /f "usebackq tokens=4" %%A in (`sc.exe query DiagTrack 2^>nul ^| findstr.exe /I /C:"STATE"`) do set "DIAGTRACK_STATE=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start 2^>nul ^| findstr.exe /I /C:"Start"`) do set "AUTOLOGGER_START=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled 2^>nul ^| findstr.exe /I /C:"Disabled"`) do set "WER_DISABLED=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled 2^>nul ^| findstr.exe /I /C:"Disabled"`) do set "WER_POLICY_DISABLED=%%A"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$c=Get-Command Get-WindowsErrorReporting -ErrorAction SilentlyContinue;if($null -eq $c){'UNKNOWN';exit 0};if(Get-WindowsErrorReporting -ErrorAction Stop){'ENABLED'}else{'DISABLED'}}catch{'UNKNOWN'}" 2^>nul`) do set "WER_EFFECTIVE=%%A"
for /f "usebackq tokens=3" %%A in (`reg.exe query "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start 2^>nul ^| findstr.exe /I /C:"Start"`) do set "WAAS_VERIFY=%%A"

if /I "%LOCAL_TELEMETRY%"=="0x3" (call :LOG "Optional diagnostic data preference : PASS (%LOCAL_TELEMETRY%)") else (
    call :LOG "Optional diagnostic data preference : FAIL (Current=%LOCAL_TELEMETRY% Expected=0x3)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% DiagnosticData"
)
if /I "%POLICY_TELEMETRY%"=="0x3" (
    if "%GPO_PERSIST_DEPLOYED%"=="1" (
        call :LOG "Diagnostic data policy              : PASS (AllowTelemetry=%POLICY_TELEMETRY% via GPO Override Task)"
    ) else (
        call :LOG "Diagnostic data policy              : PASS (AllowTelemetry=%POLICY_TELEMETRY%)"
    )
) else (
    call :LOG "Diagnostic data policy              : FAIL (Current=%POLICY_TELEMETRY% Expected=0x3)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% ManagedTelemetryPolicy"
)
if %WINDOWS_BUILD_NUM% LSS 16299 (
    if /I "%LEGACY_PREVIEW%"=="0x1" (call :LOG "Preview-build policy                : PASS (AllowBuildPreview=%LEGACY_PREVIEW%)") else (
        call :LOG "Preview-build policy                : FAIL (Current=%LEGACY_PREVIEW% Expected=0x1)"
        set "VERIFY_FAIL=1"
        set "FAIL_REASONS=%FAIL_REASONS% PreviewPolicy"
    )
) else (
    if /I "%PREVIEW%"=="0x2" (call :LOG "Preview-build policy                : PASS (ManagePreviewBuilds=%PREVIEW%)") else (
        call :LOG "Preview-build policy                : FAIL (Current=%PREVIEW% Expected=0x2)"
        set "VERIFY_FAIL=1"
        set "FAIL_REASONS=%FAIL_REASONS% PreviewPolicy"
    )
)
if /I "%DIAGTRACK_START%"=="AUTO_START" (call :LOG "DiagTrack startup                   : PASS (%DIAGTRACK_START%)") else (
    call :LOG "DiagTrack startup                   : FAIL (Current=%DIAGTRACK_START% Expected=AUTO_START)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% DiagTrack"
)
if /I "%DIAGTRACK_STATE%"=="RUNNING" (call :LOG "DiagTrack runtime state             : PASS (%DIAGTRACK_STATE%)") else (
    call :LOG "DiagTrack runtime state             : FAIL (Current=%DIAGTRACK_STATE% Expected=RUNNING)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% DiagTrackNotRunning"
)

for %%S in (wuauserv BITS UsoSvc DoSvc wlidsvc) do call :VerifyServiceNotDisabled "%%S"

if /I "%WAAS_VERIFY%"=="0x4" (
    call :LOG "Service WaaSMedicSvc                : FAIL (DISABLED)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WaaSMedicSvc"
) else if not defined WAAS_VERIFY (
    call :LOG "Service WaaSMedicSvc                : REVIEW (Start value not found)"
) else call :LOG "Service WaaSMedicSvc                : PASS (Start=%WAAS_VERIFY%)"

if /I "%AUTOLOGGER_START%"=="0x1" (call :LOG "Diagtrack AutoLogger                : PASS (%AUTOLOGGER_START%)") else (
    call :LOG "Diagtrack AutoLogger                : FAIL (Current=%AUTOLOGGER_START% Expected=0x1)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% AutoLogger"
)
if defined WER_POLICY_DISABLED (
    call :LOG "Windows Error Reporting policy      : FAIL (Policy Disabled=%WER_POLICY_DISABLED%)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WERPolicy"
) else if /I "%WER_EFFECTIVE%"=="ENABLED" (call :LOG "Windows Error Reporting             : PASS (Enabled)") else if /I "%WER_EFFECTIVE%"=="DISABLED" (
    call :LOG "Windows Error Reporting             : FAIL (Effective state disabled)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WER"
) else if defined WER_DISABLED (
    call :LOG "Windows Error Reporting             : FAIL (Disabled override=%WER_DISABLED%)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WER"
) else call :LOG "Windows Error Reporting             : REVIEW (effective state unavailable)"

call :VerifyScheduledTask "\Microsoft\Windows\Application Experience\" "Microsoft Compatibility Appraiser" "Compatibility Appraiser" 1
call :VerifyScheduledTask "\Microsoft\Windows\Feedback\Siuf\" "DmClient" "Feedback DmClient" 1
call :VerifyScheduledTask "\Microsoft\Windows\Feedback\Siuf\" "DmClientOnScenarioDownload" "Feedback scenario client" 1
call :VerifyScheduledTask "\Microsoft\Windows\Windows Error Reporting\" "QueueReporting" "WER QueueReporting" 1
call :VerifyScheduledTask "\Microsoft\Windows\Customer Experience Improvement Program\" "Consolidator" "CEIP Consolidator" 0
call :VerifyScheduledTask "\Microsoft\Windows\Customer Experience Improvement Program\" "UsbCeip" "CEIP UsbCeip" 0
call :VerifyScheduledTask "\Microsoft\Windows\DiskDiagnostic\" "Microsoft-Windows-DiskDiagnosticDataCollector" "Disk diagnostic collector" 0
call :VerifyScheduledTask "\Microsoft\Windows\Autochk\" "Proxy" "Autochk Proxy" 0
if "%PROFILE_REPAIR_WARNING%"=="1" call :LOG "User feedback-frequency cleanup     : REVIEW (one or more profiles could not be repaired)"
if "%FAILED%"=="1" (
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WriteFailure"
)
call :LOG "----------------------------------------------------------------"
exit /b 0

:VerifyServiceNotDisabled
set "SVC_NAME=%~1"
set "SVC_START="
set "SVC_PAD=%SVC_NAME%                            "
set "SVC_PAD=%SVC_PAD:~0,27%"
for /f "usebackq tokens=4" %%A in (`sc.exe qc %SVC_NAME% 2^>nul ^| findstr.exe /I /C:"START_TYPE"`) do set "SVC_START=%%A"
if /I "%SVC_START%"=="DISABLED" (
    call :LOG "Service %SVC_PAD% : FAIL (DISABLED)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% %SVC_NAME%"
) else if not defined SVC_START (
    call :LOG "Service %SVC_PAD% : UNKNOWN"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% %SVC_NAME%"
) else call :LOG "Service %SVC_PAD% : PASS (%SVC_START%)"
set "SVC_NAME="
set "SVC_START="
set "SVC_PAD="
exit /b 0

:VerifyScheduledTask
set "VERIFY_TASK_PATH=%~1"
set "VERIFY_TASK_NAME=%~2"
set "VERIFY_TASK_DISPLAY=%~3"
set "VERIFY_TASK_CRITICAL=%~4"
set "VERIFY_TASK_STATE=NOT_PRESENT"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$t=Get-ScheduledTask -TaskPath $env:VERIFY_TASK_PATH -TaskName $env:VERIFY_TASK_NAME -ErrorAction Stop;if($t.State -eq 'Disabled'){'DISABLED'}else{'ENABLED'}}catch{'NOT_PRESENT'}" 2^>nul`) do set "VERIFY_TASK_STATE=%%A"
if /I "%VERIFY_TASK_STATE%"=="DISABLED" goto :VerifyScheduledTaskDisabled
if /I "%VERIFY_TASK_STATE%"=="ENABLED" goto :VerifyScheduledTaskEnabled
call :LOG "%VERIFY_TASK_DISPLAY% task: NOT PRESENT (tolerated)"
goto :VerifyScheduledTaskDone
:VerifyScheduledTaskDisabled
if "%VERIFY_TASK_CRITICAL%"=="1" (
    call :LOG "%VERIFY_TASK_DISPLAY% task: FAIL (Disabled)"
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% Task:%VERIFY_TASK_NAME%"
) else call :LOG "%VERIFY_TASK_DISPLAY% task: REVIEW (Disabled)"
goto :VerifyScheduledTaskDone
:VerifyScheduledTaskEnabled
call :LOG "%VERIFY_TASK_DISPLAY% task: PASS (Enabled)"
:VerifyScheduledTaskDone
set "VERIFY_TASK_PATH="
set "VERIFY_TASK_NAME="
set "VERIFY_TASK_DISPLAY="
set "VERIFY_TASK_CRITICAL="
set "VERIFY_TASK_STATE="
exit /b 0
