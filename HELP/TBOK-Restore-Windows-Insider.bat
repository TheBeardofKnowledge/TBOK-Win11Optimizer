@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ============================================================================
REM TBOK Restore Windows Insider - v6
REM Restores Windows Insider, Windows diagnostic-data, WER, compatibility,
REM feedback-task, and update prerequisites changed by TBOK optimization.
REM
REM Windows 10 / Windows 11 aware.
REM This utility restores Windows Insider prerequisites only.
REM It does NOT automatically enroll the computer into an Insider channel.
REM After successful completion, restart Windows and complete enrollment
REM through the Windows Insider Program page in Settings.
REM Unrelated TBOK privacy preferences are intentionally preserved.
REM ============================================================================

REM ---------------------------------------------------------------------------
REM Administrative elevation
REM ---------------------------------------------------------------------------
fltmc.exe >nul 2>&1
if errorlevel 1 goto :RequestElevation
goto :InsiderRestoreElevated

:RequestElevation
echo Requesting administrative elevation...
set "TBOK_INSIDER_SCRIPT=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Command ^
    "try {$p=Start-Process -FilePath $env:TBOK_INSIDER_SCRIPT -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit [int]$p.ExitCode} catch {Write-Error $_.Exception.Message; exit 1}"
exit /b %ERRORLEVEL%

:InsiderRestoreElevated

REM ---------------------------------------------------------------------------
REM Detect Windows build / family / edition
REM ProductName is not a reliable Windows 10/11 discriminator after upgrades.
REM Windows 11 begins at build 22000, so the kernel build is authoritative.
REM ---------------------------------------------------------------------------
set "WINDOWS_BUILD="
set "WINDOWS_BUILD_NUM="
set "WINDOWS_PRODUCT="
set "WINDOWS_FAMILY="
set "WINDOWS_DISPLAYVERSION="

for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr.exe /I /C:"CurrentBuildNumber"') do set "WINDOWS_BUILD=%%A"
for /f "tokens=2,*" %%A in ('reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul ^| findstr.exe /I /C:"ProductName"') do set "WINDOWS_PRODUCT=%%B"
for /f "tokens=2,*" %%A in ('reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr.exe /I /C:"DisplayVersion"') do set "WINDOWS_DISPLAYVERSION=%%B"

if not defined WINDOWS_BUILD (
    echo ERROR: Windows build number could not be determined.
    echo.
    pause
    exit /b 1
)

set /a "WINDOWS_BUILD_NUM=%WINDOWS_BUILD%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows build number is not numeric: %WINDOWS_BUILD%
    echo.
    pause
    exit /b 1
)

if %WINDOWS_BUILD_NUM% GEQ 22000 (
    set "WINDOWS_FAMILY=Windows 11"
) else (
    set "WINDOWS_FAMILY=Windows 10"
)

if not defined WINDOWS_PRODUCT set "WINDOWS_PRODUCT=Unknown edition"
if not defined WINDOWS_DISPLAYVERSION set "WINDOWS_DISPLAYVERSION=Unknown"

cls
echo ================================================================
echo TBOK Windows Insider Program Restore - v6
echo ================================================================
echo OS              : %WINDOWS_FAMILY%
echo Edition string  : %WINDOWS_PRODUCT%
echo Display version : %WINDOWS_DISPLAYVERSION%
echo Build           : %WINDOWS_BUILD%
echo ================================================================
echo.
echo Restoring Windows Insider and related diagnostic settings...
echo.

set "FAILED=0"
set "VERIFY_FAIL=0"
set "FAIL_REASONS="
set "PROFILE_REPAIR_WARNING=0"

REM ---------------------------------------------------------------------------
REM Step 1 - Restore diagnostic-data policy and DiagTrack AutoLogger
REM ---------------------------------------------------------------------------
echo [1/8] Restoring diagnostic-data control...

REM Remove restrictive policy values written by TBOK.
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f >nul 2>&1

REM Restore the local Windows preference to Optional/Full diagnostic data.
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 3 /f >nul 2>&1
if errorlevel 1 set "FAILED=1"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v MaxTelemetryAllowed /t REG_DWORD /d 3 /f >nul 2>&1
if errorlevel 1 set "FAILED=1"

REM TBOK explicitly disables this boot AutoLogger on applicable SKUs.
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 set "FAILED=1"

REM Restore the same AutoLogger in the mapped Default control set.
set "DEFAULT_CONTROL_SET="
for /f "tokens=3" %%A in ('reg.exe query "HKLM\SYSTEM\Select" /v Default 2^>nul ^| findstr.exe /I /C:"Default"') do call :ResolveDefaultControlSet %%A

if defined DEFAULT_CONTROL_SET (
    reg.exe add "HKLM\SYSTEM\%DEFAULT_CONTROL_SET%\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f >nul 2>&1
    if errorlevel 1 set "FAILED=1"
) else (
    echo NOTICE: Default control-set mapping could not be resolved. CurrentControlSet was still restored.
)

REM ---------------------------------------------------------------------------
REM Step 2 - Restore preview-build policy availability
REM ---------------------------------------------------------------------------
echo [2/8] Restoring preview-build policy controls...

REM Windows 10 through 1703 uses legacy AllowBuildPreview.
REM Windows 10 1709+ and Windows 11 use ManagePreviewBuilds.
if %WINDOWS_BUILD_NUM% LSS 16299 (
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview /t REG_DWORD /d 1 /f >nul 2>&1
    if errorlevel 1 set "FAILED=1"
    reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds /f >nul 2>&1
) else (
    REM Value 3 leaves Preview Build selection to the user.
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds /t REG_DWORD /d 3 /f >nul 2>&1
    if errorlevel 1 set "FAILED=1"
    reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview /f >nul 2>&1
)

REM Remove stale feature-update targeting/deferral values that can constrain
REM preview availability. This does not force a channel.
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v BranchReadinessLevel /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdates /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdatesPeriodInDays /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v PauseFeatureUpdatesStartTime /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersion /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersionInfo /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ProductVersion /f >nul 2>&1

REM ---------------------------------------------------------------------------
REM Step 3 - Restore service availability
REM ---------------------------------------------------------------------------
echo [3/8] Restoring required service availability...

sc.exe config DiagTrack start= auto >nul 2>&1
if errorlevel 1 set "FAILED=1"
sc.exe start DiagTrack >nul 2>&1

REM Preserve usable wuauserv/BITS configurations; repair only Disabled.
sc.exe qc wuauserv 2>nul | findstr.exe /I /C:"DISABLED" >nul
if not errorlevel 1 (
    sc.exe config wuauserv start= demand >nul 2>&1
    if errorlevel 1 set "FAILED=1"
)

sc.exe qc BITS 2>nul | findstr.exe /I /C:"DISABLED" >nul
if not errorlevel 1 (
    sc.exe config BITS start= demand >nul 2>&1
    if errorlevel 1 set "FAILED=1"
)

REM ---------------------------------------------------------------------------
REM Step 4 - Restore Windows Error Reporting
REM ---------------------------------------------------------------------------
echo [4/8] Restoring Windows Error Reporting...

reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled /f >nul 2>&1
reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled /f >nul 2>&1

REM Invoke the supported WER cmdlet when present. Absence is tolerated.
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "try {$c=Get-Command Enable-WindowsErrorReporting -ErrorAction SilentlyContinue; if($null -ne $c){$r=Enable-WindowsErrorReporting -ErrorAction Stop; if($r -eq $false){exit 1}}; exit 0} catch {exit 1}" >nul 2>&1
if errorlevel 1 set "FAILED=1"

REM ---------------------------------------------------------------------------
REM Step 5 - Restore TBOK-disabled diagnostic/feedback scheduled tasks
REM ---------------------------------------------------------------------------
echo [5/8] Restoring diagnostic scheduled tasks when present...

schtasks.exe /Change /TN "\Microsoft\Windows\Feedback\Siuf\DmClient" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /ENABLE >nul 2>&1
schtasks.exe /Change /TN "\Microsoft\Windows\Autochk\Proxy" /ENABLE >nul 2>&1

REM ---------------------------------------------------------------------------
REM Step 6 - Remove TBOK SIUF feedback-frequency suppression from user profiles
REM ---------------------------------------------------------------------------
echo [6/8] Restoring default Windows feedback-frequency behavior...

set "TBOK_PROFILE_REPAIR=%TEMP%\TBOK-Insider-ProfileRepair-%RANDOM%-%RANDOM%.txt"
powershell.exe -NoLogo -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$failed=0;$changed=0;$skipped=0;" ^
    "function Repair-Hive([string]$root){try{$p='Registry::'+$root+'\SOFTWARE\Microsoft\Siuf\Rules';if(Test-Path -LiteralPath $p){$v=Get-ItemProperty -LiteralPath $p -Name NumberOfSIUFInPeriod -ErrorAction SilentlyContinue;if($null -ne $v){Remove-ItemProperty -LiteralPath $p -Name NumberOfSIUFInPeriod -Force -ErrorAction Stop;$script:changed++}else{$script:skipped++}}else{$script:skipped++}}catch{Write-Output ('ERROR='+$root+': '+$_.Exception.Message);$script:failed++}};" ^
    "$loaded=@(Get-ChildItem Registry::HKEY_USERS -ErrorAction Stop|Where-Object{$_.PSChildName -match '^S-1-(5-21|12-1)-' -and $_.PSChildName -notmatch '_Classes$'});" ^
    "foreach($h in $loaded){Repair-Hive ('HKEY_USERS\'+$h.PSChildName)};" ^
    "$profiles=@(Get-CimInstance Win32_UserProfile -ErrorAction Stop|Where-Object{-not $_.Special -and $_.LocalPath});" ^
    "foreach($p in $profiles){if($p.Loaded){continue};$nt=Join-Path $p.LocalPath 'NTUSER.DAT';if(-not(Test-Path -LiteralPath $nt)){continue};$mount='TBOKInsider_'+([guid]::NewGuid().ToString('N'));$target='HKU\'+$mount;$o=@(& reg.exe load $target $nt 2>&1);if($LASTEXITCODE -ne 0){Write-Output ('ERROR='+$p.LocalPath+': hive load failed');$failed++;continue};try{Repair-Hive ('HKEY_USERS\'+$mount)}finally{[gc]::Collect();[gc]::WaitForPendingFinalizers();$null=& reg.exe unload $target 2>&1;if($LASTEXITCODE -ne 0){Write-Output ('ERROR='+$p.LocalPath+': hive unload failed');$failed++}}};" ^
    "$defaultNt=Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT';" ^
    "if(Test-Path -LiteralPath $defaultNt){$mount='TBOKInsider_Default';$target='HKU\'+$mount;$o=@(& reg.exe load $target $defaultNt 2>&1);if($LASTEXITCODE -eq 0){try{Repair-Hive ('HKEY_USERS\'+$mount)}finally{[gc]::Collect();[gc]::WaitForPendingFinalizers();$null=& reg.exe unload $target 2>&1;if($LASTEXITCODE -ne 0){Write-Output 'ERROR=Default profile: hive unload failed';$failed++}}}else{Write-Output 'ERROR=Default profile: hive load failed';$failed++}};" ^
    "Write-Output ('CHANGED='+$changed);Write-Output ('SKIPPED='+$skipped);Write-Output ('FAILED='+$failed);if($failed -gt 0){exit 1}else{exit 0}" >"%TBOK_PROFILE_REPAIR%" 2>&1
set "PROFILE_REPAIR_RC=%ERRORLEVEL%"

type "%TBOK_PROFILE_REPAIR%" 2>nul
if exist "%TBOK_PROFILE_REPAIR%" del /q "%TBOK_PROFILE_REPAIR%" >nul 2>&1
set "TBOK_PROFILE_REPAIR="

REM SIUF is not an Insider enrollment prerequisite. Do not fail the whole repair
REM because one stale/offline user profile could not be modified.
if not "%PROFILE_REPAIR_RC%"=="0" set "PROFILE_REPAIR_WARNING=1"

REM Tailored experiences, advertising, Edge diagnostics, and Office telemetry
REM preferences are intentionally preserved. They are not Insider prerequisites.

REM ---------------------------------------------------------------------------
REM Step 7 - Refresh computer policy
REM ---------------------------------------------------------------------------
echo [7/8] Refreshing computer policy...
gpupdate.exe /target:computer /force >nul 2>&1

REM ---------------------------------------------------------------------------
REM Step 8 - Detailed verification
REM ---------------------------------------------------------------------------
echo [8/8] Verifying restored prerequisites...
echo.
echo VERIFICATION RESULTS
echo ----------------------------------------------------------------

set "LOCAL_TELEMETRY="
set "POLICY_TELEMETRY="
set "PREVIEW="
set "LEGACY_PREVIEW="
set "DIAGTRACK_START="
set "WUAUSERV_START="
set "BITS_START="
set "AUTOLOGGER_START="
set "WER_DISABLED="
set "WER_EFFECTIVE=UNKNOWN"

for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"') do set "LOCAL_TELEMETRY=%%A"
for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul ^| findstr.exe /I /C:"AllowTelemetry"') do set "POLICY_TELEMETRY=%%A"

if %WINDOWS_BUILD_NUM% LSS 16299 (
    for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" /v AllowBuildPreview 2^>nul ^| findstr.exe /I /C:"AllowBuildPreview"') do set "LEGACY_PREVIEW=%%A"
) else (
    for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuilds 2^>nul ^| findstr.exe /I /C:"ManagePreviewBuilds"') do set "PREVIEW=%%A"
)

for /f "tokens=4" %%A in ('sc.exe qc DiagTrack 2^>nul ^| findstr.exe /I /C:"START_TYPE"') do set "DIAGTRACK_START=%%A"
for /f "tokens=4" %%A in ('sc.exe qc wuauserv 2^>nul ^| findstr.exe /I /C:"START_TYPE"') do set "WUAUSERV_START=%%A"
for /f "tokens=4" %%A in ('sc.exe qc BITS 2^>nul ^| findstr.exe /I /C:"START_TYPE"') do set "BITS_START=%%A"
for /f "tokens=3" %%A in ('reg.exe query "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start 2^>nul ^| findstr.exe /I /C:"Start"') do set "AUTOLOGGER_START=%%A"
for /f "tokens=3" %%A in ('reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled 2^>nul ^| findstr.exe /I /C:"Disabled"') do set "WER_DISABLED=%%A"

for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$c=Get-Command Get-WindowsErrorReporting -ErrorAction SilentlyContinue;if($null -eq $c){'UNKNOWN';exit 0};if(Get-WindowsErrorReporting -ErrorAction Stop){'ENABLED'}else{'DISABLED'}}catch{'UNKNOWN'}" 2^>nul`) do set "WER_EFFECTIVE=%%A"

if /I "%LOCAL_TELEMETRY%"=="0x3" (
    echo Optional diagnostic data preference : PASS ^(%LOCAL_TELEMETRY%^)
) else (
    echo Optional diagnostic data preference : FAIL ^(Current=%LOCAL_TELEMETRY% Expected=0x3^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% DiagnosticData"
)

if defined POLICY_TELEMETRY (
    echo Restrictive diagnostic policy       : REVIEW ^(AllowTelemetry=%POLICY_TELEMETRY%^)
    if /I not "%POLICY_TELEMETRY%"=="0x3" (
        set "VERIFY_FAIL=1"
        set "FAIL_REASONS=%FAIL_REASONS% ManagedTelemetryPolicy"
    )
) else (
    echo Restrictive diagnostic policy       : PASS ^(No local AllowTelemetry policy remains^)
)

if %WINDOWS_BUILD_NUM% LSS 16299 (
    if /I "%LEGACY_PREVIEW%"=="0x1" (
        echo Preview-build policy             : PASS ^(AllowBuildPreview=%LEGACY_PREVIEW%^)
    ) else (
        echo Preview-build policy             : FAIL ^(AllowBuildPreview=%LEGACY_PREVIEW% Expected=0x1^)
        set "VERIFY_FAIL=1"
        set "FAIL_REASONS=%FAIL_REASONS% PreviewPolicy"
    )
) else (
    if /I "%PREVIEW%"=="0x3" (
        echo Preview-build policy             : PASS ^(ManagePreviewBuilds=%PREVIEW%^)
    ) else (
        echo Preview-build policy             : FAIL ^(ManagePreviewBuilds=%PREVIEW% Expected=0x3^)
        set "VERIFY_FAIL=1"
        set "FAIL_REASONS=%FAIL_REASONS% PreviewPolicy"
    )
)

if /I "%DIAGTRACK_START%"=="AUTO_START" (
    echo DiagTrack startup                    : PASS ^(%DIAGTRACK_START%^)
) else (
    echo DiagTrack startup                    : FAIL ^(Current=%DIAGTRACK_START% Expected=AUTO_START^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% DiagTrack"
)

if /I "%WUAUSERV_START%"=="DISABLED" (
    echo Windows Update service               : FAIL ^(DISABLED^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WindowsUpdate"
) else if not defined WUAUSERV_START (
    echo Windows Update service               : UNKNOWN
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WindowsUpdate"
) else (
    echo Windows Update service               : PASS ^(%WUAUSERV_START%^)
)

if /I "%BITS_START%"=="DISABLED" (
    echo BITS service                         : FAIL ^(DISABLED^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% BITS"
) else if not defined BITS_START (
    echo BITS service                         : UNKNOWN
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% BITS"
) else (
    echo BITS service                         : PASS ^(%BITS_START%^)
)

if /I "%AUTOLOGGER_START%"=="0x1" (
    echo Diagtrack AutoLogger                 : PASS ^(%AUTOLOGGER_START%^)
) else (
    echo Diagtrack AutoLogger                 : FAIL ^(Current=%AUTOLOGGER_START% Expected=0x1^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% AutoLogger"
)

if /I "%WER_EFFECTIVE%"=="ENABLED" (
    echo Windows Error Reporting              : PASS ^(Enabled^)
) else if /I "%WER_EFFECTIVE%"=="DISABLED" (
    echo Windows Error Reporting              : FAIL ^(Effective state disabled^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WER"
) else if defined WER_DISABLED (
    echo Windows Error Reporting              : FAIL ^(Disabled override=%WER_DISABLED%^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WER"
) else (
    echo Windows Error Reporting              : REVIEW ^(No Disabled override; effective state unavailable^)
)

REM Verify core diagnostic tasks. Missing tasks are tolerated across releases.
call :VerifyScheduledTask "\Microsoft\Windows\Application Experience\" "Microsoft Compatibility Appraiser" "Compatibility Appraiser" 1
call :VerifyScheduledTask "\Microsoft\Windows\Feedback\Siuf\" "DmClient" "Feedback DmClient" 1
call :VerifyScheduledTask "\Microsoft\Windows\Feedback\Siuf\" "DmClientOnScenarioDownload" "Feedback scenario client" 1
call :VerifyScheduledTask "\Microsoft\Windows\Windows Error Reporting\" "QueueReporting" "WER QueueReporting" 1

REM Supplemental diagnostic tasks report REVIEW rather than failing the repair.
call :VerifyScheduledTask "\Microsoft\Windows\Customer Experience Improvement Program\" "Consolidator" "CEIP Consolidator" 0
call :VerifyScheduledTask "\Microsoft\Windows\Customer Experience Improvement Program\" "UsbCeip" "CEIP UsbCeip" 0
call :VerifyScheduledTask "\Microsoft\Windows\DiskDiagnostic\" "Microsoft-Windows-DiskDiagnosticDataCollector" "Disk diagnostic collector" 0
call :VerifyScheduledTask "\Microsoft\Windows\Autochk\" "Proxy" "Autochk Proxy" 0

echo ----------------------------------------------------------------

if "%PROFILE_REPAIR_WARNING%"=="1" (
    echo User feedback-frequency cleanup     : REVIEW ^(one or more profiles could not be repaired^)
)

if "%FAILED%"=="1" (
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% WriteFailure"
)

if "%VERIFY_FAIL%"=="0" goto :SUCCESS
goto :FAILURE

:SUCCESS
echo.
echo ================================================================
echo WINDOWS INSIDER RESTORATION COMPLETED SUCCESSFULLY
echo ================================================================
echo.
echo The Windows settings and services modified by TBOK that can affect
echo Windows Insider enrollment and diagnostic reporting have been restored.
echo.
echo IMPORTANT:
echo This computer has NOT automatically been enrolled in an Insider channel.
echo Windows must be restarted before completing Insider enrollment.
echo.
echo ----------------------------------------------------------------
echo NEXT STEPS
echo ----------------------------------------------------------------
echo.
echo 1. Restart this computer.
echo.

if %WINDOWS_BUILD_NUM% LSS 22000 (
    echo 2. After restarting, open:
    echo.
    echo       Settings
    echo         ^> Update ^& Security
    echo         ^> Windows Insider Program
) else (
    echo 2. After restarting, open:
    echo.
    echo       Settings
    echo         ^> Windows Update
    echo         ^> Windows Insider Program
)

echo.
echo 3. If Windows asks for additional diagnostic data, confirm that
echo    Send optional diagnostic data is enabled.
echo.
echo 4. Select Get started if the computer is not already enrolled.
echo.
echo 5. Link the Microsoft account or organizational account registered
echo    with the Windows Insider Program when Windows requests it.
echo.
echo 6. Select the Insider channel that Windows currently offers and that
echo    is appropriate for this computer.
echo.
echo 7. Accept the Windows Insider terms if prompted.
echo.
echo 8. Restart Windows again if the Insider Program page requests it.
echo.
echo 9. Return to Windows Update and select Check for updates.
echo.
echo ----------------------------------------------------------------
echo IMPORTANT NOTES
echo ----------------------------------------------------------------
echo.
echo - This utility does not force Dev, Beta, Release Preview, or any
echo   other Insider channel.
echo.
echo - Channel availability is determined by Microsoft, the Windows build,
echo   hardware compatibility, account eligibility, and management policy.
echo.
echo - Domain Group Policy, Intune/MDM, WSUS, or Configuration Manager can
echo   override settings restored by this utility.
echo.
echo - Running TBOK optimization again may reapply privacy or diagnostic
echo   restrictions that can interfere with Windows Insider functionality.
echo.
echo - Unrelated privacy preferences such as advertising, tailored
echo   experiences, Edge diagnostic preferences, and Office telemetry were
echo   intentionally left unchanged.
echo.
echo ================================================================
echo Restart Windows before evaluating the Windows Insider Program page.
echo ================================================================
echo.
echo Press any key to close this window...
pause >nul
exit /b 0

:FAILURE
echo.
echo RESULT: Windows Insider prerequisites are NOT fully restored.
echo Failed areas:%FAIL_REASONS%
echo.
echo Common causes on Windows Enterprise include:
echo   - Domain Group Policy reapplying diagnostic-data restrictions.
echo   - Intune/MDM enforcing telemetry or Windows Update for Business policy.
echo   - WSUS or Configuration Manager controlling Windows Update.
echo   - A previous privacy/debloat policy being reapplied.
echo.
echo Generate a policy report with:
echo   gpresult /h "%TEMP%\TBOK-Insider-GPResult.html"
echo.
echo Press any key to close this window...
pause >nul
exit /b 1

REM ===========================================================================
REM Helpers
REM ===========================================================================

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

:VerifyScheduledTask
REM Usage: call :VerifyScheduledTask "TaskPath" "TaskName" "DisplayName" CriticalFlag
set "VERIFY_TASK_PATH=%~1"
set "VERIFY_TASK_NAME=%~2"
set "VERIFY_TASK_DISPLAY=%~3"
set "VERIFY_TASK_CRITICAL=%~4"
set "VERIFY_TASK_STATE=NOT_PRESENT"

for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try{$t=Get-ScheduledTask -TaskPath $env:VERIFY_TASK_PATH -TaskName $env:VERIFY_TASK_NAME -ErrorAction Stop;if($t.State -eq 'Disabled'){'DISABLED'}else{'ENABLED'}}catch{'NOT_PRESENT'}" 2^>nul`) do set "VERIFY_TASK_STATE=%%A"

if /I "%VERIFY_TASK_STATE%"=="DISABLED" goto :VerifyScheduledTaskDisabled
if /I "%VERIFY_TASK_STATE%"=="ENABLED" goto :VerifyScheduledTaskEnabled

echo %VERIFY_TASK_DISPLAY% task : NOT PRESENT ^(tolerated^)
goto :VerifyScheduledTaskDone

:VerifyScheduledTaskDisabled
if "%VERIFY_TASK_CRITICAL%"=="1" (
    echo %VERIFY_TASK_DISPLAY% task : FAIL ^(Disabled^)
    set "VERIFY_FAIL=1"
    set "FAIL_REASONS=%FAIL_REASONS% Task:%VERIFY_TASK_NAME%"
) else (
    echo %VERIFY_TASK_DISPLAY% task : REVIEW ^(Disabled^)
)
goto :VerifyScheduledTaskDone

:VerifyScheduledTaskEnabled
echo %VERIFY_TASK_DISPLAY% task : PASS ^(Enabled^)

:VerifyScheduledTaskDone
set "VERIFY_TASK_PATH="
set "VERIFY_TASK_NAME="
set "VERIFY_TASK_DISPLAY="
set "VERIFY_TASK_CRITICAL="
set "VERIFY_TASK_STATE="
exit /b 0
