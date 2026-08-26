::turn off echoing all commands
@ECHO OFF
::change the terminal color to something friendlier
color f0
:: Automatically check and get admin rights ::
ECHO Elevating permissions required for Admin access
ECHO No changes are being made at this time.

:checkPrivileges 
	NET FILE 1>NUL 2>NUL
	if '%errorlevel%' == '0' ( goto gotPrivileges ) else ( goto getPrivileges ) 
:getPrivileges
:: Not elevated, so re-run with elevation
    	powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Start-Process '%ComSpec%' -Verb RunAs -ArgumentList '/c ""%~f0"" %*'"
    	exit /b
:gotPrivileges 

cls	
::::::::::::begin script helper objects::::::::::
::enable extended script logic and variable holding
setlocal enableextensions EnableDelayedExpansion

::Log stored in current script directory
set "LOGFILE=%~dp0TBOKWinOptimizer.log"
goto menu

:ServiceExists
sc query "%~1" >nul 2>&1
exit /b %errorlevel%

:SetServiceStartup
powershell.exe -NoProfile -Command ^
"Get-Service -Name '%~1' -ErrorAction SilentlyContinue ^| ForEach-Object { try { sc.exe config ""$($_.Name)"" start= %~2 > $null 2>&1 } catch {} }"
exit /b

::LOG and echo helper to avoid duplicate lines in script
::usage call :LOG "message to echo"
:LOG 
echo %*
>>"%LOGFILE%" echo([%DATE% %TIME%] %*
exit /b
::::::::::::end script helper objects::::::::::


:MENU
TITLE TBOK Windows Performance Optimizer
::rundll32.exe cmdext.dll,MessageBeepStub
ECHO Welcome to The Beard of Knowledge Windows Performance Optimizer
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
ECHO Welcome to The Beard of Knowledge Windows Performance Optimizer
ECHO.
ECHO Please choose
ECHO 1. Apply all improvements - except gaming tweaks -DEFAULT-
ECHO 2. Apply only user level improvements
ECHO 3. Apply only gaming tweaks
ECHO 4. EXIT
ECHO.
ECHO IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE - THATS WHAT POWERED THIS
ECHO "https://buymeacoffee.com/thebeardofl"
ECHO.
ECHO ============================================================
CHOICE /c 1234 /n /m "Enter 1-4: (Default: 1 in 10 seconds): " /t 10 /d 1
if errorlevel 4 goto :EXIT
if errorlevel 3 goto :GamingTweaks
if errorlevel 2 goto :UserTweaks
if errorlevel 1 goto :SystemTweaks



:SYSTEMTWEAKS
call :LOG Detected:
ver >> "%LOGFILE%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" >> "%LOGFILE%"

:restorepoint
call :LOG Before anything is modified - create system restore point
call :LOG Ensuring System Restore is enabled...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Enable-ComputerRestore -Drive ($env:SystemDrive + '\')" >nul 2>&1
call :LOG Checking required services...
sc query vss | find "RUNNING"
if !errorlevel! neq 0 (
    call :LOG Starting Volume Shadow Copy service...    
net start vss    
timeout /t 2 /nobreak >nul
)
call :LOG Ensuring restore point can be created immediately
REG ADD "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f
timeout /t 2 /nobreak >nul
call :LOG Creating restore point...
PowerShell -ExecutionPolicy RemoteSigned -Command "try { Checkpoint-Computer -Description 'Status Before TBOK Windows Optimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; exit 0 } catch { exit 1 }"
if !errorlevel! equ 0 (
    call :LOG Restore point created successfully.
) else (
    call :LOG WARNING: Could not create restore point.
    pause
)
:RegistryBackup
call :LOG Creating a separate registry backup just in case
reg export HKLM "%~dp0TBOK-HKLM-Registry-Backup.reg" /y >nul
reg export HKCU "%~dp0TBOK-HKCU-Registry-Backup.reg" /y >nul
call :LOG Registry backed up and saved to script folder

call :LOG Starting selected changes

:hibernation
call :LOG Setting Hibernation Mode based on PC chassis type - should be disabled for desktops - especially with SSD system drives
::	Reasons to leave Hibernation/Fast Startup/Hybrid Shutdown disabled on desktops...
::	1. Most modern PC's come with an SSD or m2 NVME drive and fast startup is not required as it was made to improve performance for systems with slower spinning disks
::	2. Hybrid shutdown/hibernation/fast startup often causes Windows Updates to NOT install properly.
::	3. "system up time" timer in task manager keeps running with this enabled.
::	4. Software with poor memory management design can cause excess ram usage
::	Only Reason to enable on a laptop:
::	Only good thing from Hibernate/Fast Startup is if your Laptop/Tablet battery reaches critical while in sleep/standby mode...
::	your open files are saved because the laptop will wake and save data in ram to hibernation file, then shutdown.

:detectchassis
	Set "Type=" & For /F EOL^=- %%G In ('
	 %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command
	 "(Get-CimInstance -Query 'Select * From CIM_Chassis').ChassisTypes"^
	 " | Select-Object -Property @{ Label = '-'; Expression = { Switch ($_) {"^
 	" { '3', '4', '5', '6', '7', '13', '15', '16', '24' -Eq $_ } { 'Desktop' };"^
 	" { '8', '9', '10', '11', '12', '14', '18', '21', '30', '31', '32' -Eq $_ } { 'Laptop' };"^
	 " default { '' } } } }" 2^>NUL') Do Set Type=%%G
	If Not Defined Type GoTo unknownchassis
	Set Type
		if /i "%Type%"=="Laptop" goto laptop
		if /i "%Type%"=="Desktop" goto desktop
		goto unknownchassis
	:laptop
		call :LOG Laptop detected - enabled hibernation "fast startup" mode
		powercfg -h on
		goto f8startup
	:desktop
		call :LOG Desktop detected - disabled hibernation "fast startup" mode
		powercfg -h off
		goto f8startup
	:unknownchassis
	call :LOG Unable to determine chassis type. Hibernation was not changed.
	
	
:F8startup
call :LOG Restoring the much beloved F8 Startup menu availability - WHY TF DID THEY REMOVE THAT
::This is optional to enable - Microsoft default wants you to power cycle your PC 2 times before giving you boot options - waste of time
::If you have bitlocker enabled - using F8 will prompt you for the recovery key when you use the legacy boot menu - be aware
bcdedit /set {default} bootmenupolicy legacy

:virtualmemory
call :LOG Optimizing windows virtual memory settings to prevent system hangs on low memory conditions due to SwapFile expansion delay
:: On low ram systems <16GB - Windows keeps the auto mode current allocation too low IMO
:: This can cause system lag-hang conditions while it expands the swap file because it filled up too soon
:: Tests have found that a minimum of 4096 or prefered 8192 is an optimal start - and max size should be double that up to a point
:: If your system has more than >=32GB of ram - just leave it on auto - Windows does a good job at that size or higher

powershell.exe -NoProfile -Command ^
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
}"
	
:SERVICES
call :LOG Enable Modern SvHost split behaviour according to currently installed RAM - works up to around 4TB of RAM
call :LOG This change the svhost process grouping to an optimized state based on your installed RAM
::This changes how many processes are grouped according to available memory - it does not actually reduce running processes
	for /f %%A in ('powershell -NoProfile -Command "(Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB"') do (set MemoryKB=%%A)
	call :LOG Memory: !MemoryKB! KB

REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" ^
  /v SvcHostSplitThresholdInKB ^
  /t REG_DWORD ^
  /d !MemoryKB! ^
  /f

call :LOG Setting Unecessary Windows Services to Optimized State

call :LOG Disabling services that are not used or should be disabled

::deprecated means service not in current versions of windows 10-11pro-ent-ltsc
::deprecated call :SetServiceStartup AJRouter disabled
call :SetServiceStartup AppVClient disabled
call :SetServiceStartup NetTcpPortSharing disabled
call :SetServiceStartup DialogBlockingService disabled
call :SetServiceStartup DiagTrack disabled
call :SetServiceStartup UevAgentService disabled
call :SetServiceStartup ssh-agent disabled
call :LOG Setting sysmain service mode based on RAM and System Disk type
::sysmain was developed to have the system load commonly used items from mechanical drives into memory for faster processing with less wait
::with the current speed of NVME drives - the sysmain services is practically irrelevant
::Findings Rule of thumb - sysmain should be disabled on systems with < 12GB ram - but benefits mechanical hard drive systems with > 12Gb RAM
::sysmain runs on second boot after install and uses about 70-mb ram as a constant process 

::powershell -NoProfile -Command "$MemGB=((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum/1GB); $Drive=$env:SystemDrive.TrimEnd(':'); $Disk=(Get-Partition -DriveLetter $Drive | Get-Disk); $IsSSD=($Disk.MediaType -eq 'SSD'); if($IsSSD){sc.exe config SysMain start= disable} elseif(($Disk.MediaType -ne 'SSD') -and ($MemGB -gt 12)){sc.exe config SysMain start= demand}"

:: Get installed memory in GB
for /f %%A in ('powershell -NoProfile -Command "[math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB),0)"') do (set MemoryGB=%%A)
:: Detect OS drive type (NVMe, SSD, HDD)
for /f "delims=" %%A in ('powershell -NoProfile -Command "$d=(Get-Partition -DriveLetter $env:SystemDrive.TrimEnd('':'') ^| Get-Disk); if($d.BusType -eq ''NVMe''){''NVMe''} elseif($d.MediaType -eq ''SSD''){''SSD''} elseif($d.MediaType -eq 'HDD'){'HDD'}else{'UNKNOWN'}"') do (
    set "DriveType=%%A"
)
call :LOG Memory: !MemoryGB! GB
call :LOG System Drive Type: !DriveType!

if /I "!DriveType!"=="NVMe" (
    call :LOG NVMe detected. Disabling SysMain...
    call :SetServiceStartup SysMain disabled
    sc stop SysMain
) else if /I "!DriveType!"=="SSD" (
    call :LOG SSD detected. Disabling SysMain...
    call :SetServiceStartup SysMain disabled
    sc stop SysMain
) else if /I "!DriveType!"=="UNKNOWN" (
    call :LOG Unable to determine drive type. Leaving SysMain unchanged.
) else (
    if !MemoryGB! GTR 12 (
        call :LOG HDD and more than 12GB RAM detected. Setting SysMain to start on demand
        call :SetServiceStartup SysMain demand
    ) else (
        call :LOG HDD with 12GB RAM or less. Setting SysMain to disabled...
        call :SetServiceStartup SysMain disabled
    )
)
call :LOG Done with services to disable

call :LOG Setting non-critical per-use services to manual startup so they can still work when needed but are not auto running on startup
call :LOG Many of these are manual by default anyway so some of this process is just to restore that behaviour in case something changed them
call :SetServiceStartup ALG demand
call :SetServiceStartup AppIDSvc demand
call :SetServiceStartup AppMgmt demand
call :SetServiceStartup AppReadiness demand
call :SetServiceStartup Appinfo demand
call :SetServiceStartup AssignedAccessManagerSvc demand
call :SetServiceStartup AxInstSV demand
call :SetServiceStartup BDESVC demand
call :SetServiceStartup  BcastDVRUserService_* demand
call :SetServiceStartup  BluetoothUserService_* demand
::deprecated call :SetServiceStartup 'Browser' demand
call :SetServiceStartup BTAGService demand
call :SetServiceStartup bthserv demand
call :SetServiceStartup  CaptureService_* demand
call :SetServiceStartup  cbdhsvc_* demand
::deprecated call :SetServiceStartup CDPSvc demand
call :SetServiceStartup CertPropSvc demand
call :SetServiceStartup cloudidsvc demand
call :SetServiceStartup COMSysApp demand
call :SetServiceStartup  ClipSVC demand
call :SetServiceStartup  ConsentUxUserSvc_* demand
call :SetServiceStartup  CredentialEnrollmentManagerUserSvc_* demand
call :SetServiceStartup CscService demand
call :SetServiceStartup  DcpSvc demand
call :SetServiceStartup dcsvc demand
call :SetServiceStartup defragsvc demand
call :SetServiceStartup DevQueryBroker demand
call :SetServiceStartup  DeviceAssociationBroker_* demand
call :SetServiceStartup DeviceAssociationService demand
call :SetServiceStartup DeviceInstall demand
call :SetServiceStartup  DevicePickerUserSvc_* demand
call :SetServiceStartup  DevicesFlowUserSvc_* demand
call :SetServiceStartup  diagnosticshub.standardcollector.service demand
call :SetServiceStartup diagsvc demand
call :SetServiceStartup DisplayEnhancementService demand
call :SetServiceStartup DmEnrollmentSvc demand
call :SetServiceStartup dmwappushservice demand
call :SetServiceStartup dot3svc demand
call :SetServiceStartup  DoSvc demand
call :SetServiceStartup  embeddedmode demand
call :SetServiceStartup fdPHost demand
call :SetServiceStartup fhsvc demand
call :SetServiceStartup hidserv demand
call :SetServiceStartup icssvc demand
call :SetServiceStartup EapHost demand
call :SetServiceStartup edgeupdate demand
call :SetServiceStartup edgeupdatem demand
call :SetServiceStartup EFS demand
call :SetServiceStartup  EntAppSvc demand
call :SetServiceStartup FDResPub demand
call :SetServiceStartup  Fax demand
call :SetServiceStartup FrameServer demand
call :SetServiceStartup FrameServerMonitor demand
call :SetServiceStartup GraphicsPerfSvc demand
::deprecated call :SetServiceStartup  HomeGroupListener demand
::deprecated call :SetServiceStartup  HomeGroupProvider demand
call :SetServiceStartup HvHost demand
call :SetServiceStartup  IEEtwCollectorService demand
call :SetServiceStartup IKEEXT demand
::ignored call :SetServiceStartup InstallService demand
call :SetServiceStartup IpxlatCfgSvc demand
call :SetServiceStartup lfsvc demand
::ignored call :SetServiceStartup LicenseManager demand
call :SetServiceStartup lltdsvc demand
call :SetServiceStartup lmhosts demand
call :SetServiceStartup LxpSvc demand
call :SetServiceStartup McpManagementService demand
call :SetServiceStartup  MessagingService_* demand
call :SetServiceStartup MicrosoftEdgeElevationService demand
call :SetServiceStartup  MixedRealityOpenXRSvc demand
call :SetServiceStartup MSDTC demand
call :SetServiceStartup MsKeyboardFilter demand
call :SetServiceStartup MSiSCSI demand
call :SetServiceStartup  msiserver demand
call :SetServiceStartup  NPSMSvc_* demand
call :SetServiceStartup NaturalAuthentication demand
call :SetServiceStartup NcaSvc demand
call :SetServiceStartup NcbService demand
call :SetServiceStartup NcdAutoSetup demand
call :SetServiceStartup NetSetupSvc demand
call :SetServiceStartup Netman demand
call :SetServiceStartup  NgcCtnrSvc demand
call :SetServiceStartup  NgcSvc demand
::call :SetServiceStartup NlaSvc demand
::call :SetServiceStartup netprofm demand
call :SetServiceStartup  p2pimsvc demand
call :SetServiceStartup  p2psvc demand
call :SetServiceStartup  P9RdrService_* demand
call :SetServiceStartup PcaSvc demand
call :SetServiceStartup PeerDistSvc demand
call :SetServiceStartup  PenService_* demand
call :SetServiceStartup perceptionsimulation demand
call :SetServiceStartup PerfHost demand
call :SetServiceStartup PhoneSvc demand
call :SetServiceStartup  PimIndexMaintenanceSvc_* demand
call :SetServiceStartup pla demand
call :SetServiceStartup PlugPlay demand
call :SetServiceStartup  PNRPAutoReg demand
call :SetServiceStartup  PNRPsvc demand
call :SetServiceStartup PolicyAgent demand
call :SetServiceStartup PrintNotify demand
call :SetServiceStartup  PrintWorkflowUserSvc_* demand
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
call :SetServiceStartup  SharedRealitySvc demand
call :SetServiceStartup shpamsvc demand
call :SetServiceStartup SmsRouter demand
call :SetServiceStartup smphost demand
call :SetServiceStartup SNMPTrap demand
call :SetServiceStartup  spectrum demand
call :SetServiceStartup SstpSvc demand
call :SetServiceStartup SSDPSRV demand
call :SetServiceStartup StiSvc demand
call :SetServiceStartup StorSvc demand
call :SetServiceStartup svsvc demand
call :SetServiceStartup swprv demand
::sysmain alphabetical placeholder
call :SetServiceStartup  TabletInputService demand
call :SetServiceStartup TapiSrv demand
call :SetServiceStartup TieringEngineService demand
call :SetServiceStartup  TimeBroker demand
call :SetServiceStartup  TimeBrokerSvc demand
::EnterpriseIgnore call :SetServiceStartup TokenBroker demand
call :SetServiceStartup TroubleshootingSvc demand
call :SetServiceStartup  UI0Detect demand
call :SetServiceStartup  UdkUserSvc_* demand
call :SetServiceStartup UmRdpService demand
call :SetServiceStartup  UnistoreSvc_* demand
call :SetServiceStartup  UserDataSvc_* demand
::EnterpriseIgnore call :SetServiceStartup UsoSvc demand
call :SetServiceStartup upnphost demand
call :SetServiceStartup  VacSvc demand
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
call :SetServiceStartup  WcsPlugInService demand
call :SetServiceStartup wcncsvc demand
call :SetServiceStartup  WdNisSvc demand
call :SetServiceStartup WdiServiceHost demand
call :SetServiceStartup WdiSystemHost demand
call :SetServiceStartup WebClient demand
call :SetServiceStartup Wecsvc demand
call :SetServiceStartup wercplsupport demand
call :SetServiceStartup WEPHOSTSVC demand
call :SetServiceStartup WerSvc demand
call :SetServiceStartup WFDSConMgrSvc demand
call :SetServiceStartup WiaRpc demand
call :SetServiceStartup  WinHttpAutoProxySvc demand
call :SetServiceStartup WinRM demand
call :SetServiceStartup wisvc demand
call :SetServiceStartup wlidsvc demand
call :SetServiceStartup wlpasvc demand
call :SetServiceStartup wmiApSrv demand
call :SetServiceStartup WMPNetworkSvc demand
call :SetServiceStartup WManSvc demand
call :SetServiceStartup WPDBusEnum demand
call :SetServiceStartup WpcMonSvc demand
::call :SetServiceStartup WpnService demand
call :SetServiceStartup workfolderssvc demand
::deprecated call :SetServiceStartup  WSService demand
call :SetServiceStartup XblAuthManager demand
call :SetServiceStartup XblGameSave demand
call :SetServiceStartup XboxNetApiSvc demand

call :LOG Done with manual services

call :LOG Ensuring required services are set to automatic State
call :LOG This is just in case you used a previous utility that set the services incorrectly -WinUtil-
call :SetServiceStartup AudioEndpointBuilder auto
call :SetServiceStartup AudioSrv auto
call :SetServiceStartup BFE auto
call :SetServiceStartup BITS auto
call :SetServiceStartup BrokerInfrastructure auto
call :SetServiceStartup BthHFSrv auto
call :SetServiceStartup CDPUserSvc_* auto
call :SetServiceStartup CoreMessagingRegistrar auto
call :SetServiceStartup CryptSvc auto
call :SetServiceStartup DPS auto
call :SetServiceStartup DcomLaunch auto
call :SetServiceStartup Dhcp auto
call :SetServiceStartup DispBrokerDesktopSvc auto
call :SetServiceStartup Dnscache auto
call :SetServiceStartup dusmsvc auto
call :SetServiceStartup EventLog auto
call :SetServiceStartup EventSystem auto
call :SetServiceStartup FontCache auto
call :SetServiceStartup gpsvc auto
call :SetServiceStartup iphlpsvc auto
call :SetServiceStartup LSM auto
call :SetServiceStartup LanmanServer auto
call :SetServiceStartup LanmanWorkstation auto
call :SetServiceStartup MpsSvc auto
call :SetServiceStartup nsi auto
call :SetServiceStartup OneSyncSvc_* auto
call :SetServiceStartup Power auto
call :SetServiceStartup ProfSvc auto
call :SetServiceStartup RpcEptMapper auto
call :SetServiceStartup RpcSs auto
::omit call :SetServiceStartup RemoteAccess auto
::omit call :SetServiceStartup RemoteRegistry auto
call :SetServiceStartup SENS auto
call :SetServiceStartup SamSs auto
call :SetServiceStartup Schedule auto
call :SetServiceStartup ShellHWDetection auto
call :SetServiceStartup Spooler auto
call :SetServiceStartup sppsvc auto
call :SetServiceStartup SystemEventsBroker auto
call :SetServiceStartup Themes auto
call :SetServiceStartup tiledatamodelsvc auto
call :SetServiceStartup TrkWks auto
call :SetServiceStartup tzautoupdate auto
call :SetServiceStartup uhssvc auto
call :SetServiceStartup UserManager auto
call :SetServiceStartup W32Time auto
call :SetServiceStartup Wcmsvc auto
call :SetServiceStartup WinDefend auto
call :SetServiceStartup Winmgmt auto
call :SetServiceStartup WlanSvc auto
call :SetServiceStartup WpnUserService_* auto

Call :LOG Changing less essential services to delayed-auto
::omit call :SetServiceStartup MapsBroker delayed-auto
call :SetServiceStartup SecurityHealthService delayed-auto
call :SetServiceStartup WSearch delayed-auto
call :SetServiceStartup wscsvc delayed-auto
call :SetServiceStartup wuauserv delayed-auto
call :SetServiceStartup wudfsvc delayed-auto
call :SetServiceStartup XboxGipSvc delayed-auto

call :LOG Windows Services Changes Completed


:machine-wide-registry
call :LOG Enabling System-wide Registry Improvements


call :LOG Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f
::alt REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f

call :LOG Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f

call :LOG Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f 

call :LOG Speed up shutdown time
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 5000 /f

call :LOG Enabling long file system path support - FR though -why is this disabled by default Microsoft
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f

call :LOG Disabling the setting that allows hardware to install whatever software it wants - LG Monitor McAffee Incident
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" /v PreventDeviceMetadataFromNetwork /t REG_DWORD /d 1 /f 

call :LOG Disable Webview dependency for Search - breaks nothing - puts search back into classic mode
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledState /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledStateOptions /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v Variant /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayload /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayloadKind  /t REG_DWORD /d 0 /f

call :LOG Turning off telemetry data collection Local Machine
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f
REG ADD "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 0 /f
::next lines possibly eol but have been documented by MS - possibly older telemitry framework
REG ADD "HKLM\SYSTEM\ControlSet001\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /t REG_DWORD /d 0 /f

::call :LOG Wi-Fi Sense Disable affects devices autoconnecting - leaving enabled
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f

::call :LOG Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f

call :LOG Enable verbose logon-off status on shutdown screen -optional but helpful
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v VerboseStatus /t REG_DWORD /d 1 /f

::this section might not apply - testing needed
call :LOG Disable privacy settings experience at first OOBE logon
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v SkipMachineOOBE /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisableVoice /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v Protectyourpc /t REG_DWORD /d 3 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v HideEULAPage /t REG_DWORD /d 1 /f

call :LOG Disable the lock screen which includes personalized ads - MS Spotlight ads- Default 0
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f

::call :LOG Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has a known vulnerability
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f
	
call :LOG Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f	
REG ADD "HKLM\SYSTEM\ControlSet001\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f

::For system hardening only - sometimes slows shutdown time
::call :LOG clear page file at shutdown to remove sensitive memory remnants from pagefile.sys - rebuilds each boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f

call :LOG Fix Network Data Usage Graph not working
REG ADD "HKLM\SYSTEM\ControlSet001\Services\Ndu" /v Start /t REG_DWORD /d 2 /f

:systemtelemitry
call :LOG ==Disable Windows System Telemetry==
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f

call :LOG Disable Powershell telemitry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f
call :LOG System level registry tweaks completed


::call :LOG Disable GameDVR - not recommended on AMD X3d chips due to CCD cache routing
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f

call :LOG =================edge tweaks=================
call :LOG Disable Edge so-called start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f

call :LOG Disable exhaustive Edge first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f

call :LOG Disabling submit user feedback because Microsoft does not actually listen - worthless
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f

call :LOG Disabling shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f

::call :LOG Disabling gamer mode for Edge so it doesnt monitor your active applications
::call :LOG While this serves to lower resource usage for the browser - it also monitors everything running
::REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 0 /f

call :LOG ===============end edge tweaks=================


:: =======Disable Microsoft Office telemetry agent==========
call :LOG --- Disable Microsoft Office telemetry agent
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentFallBack`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentFallBack'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentFallBack2016`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentFallBack2016'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentLogOn`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentLogOn'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentLogOn2016`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentLogOn2016'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"

call :LOG Time for some bloat removal

call :LOG Remove and Disable Windows Co-pilot -standard- machine wide settings
::Enable reg key that allows app to be uninstalled
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
call :LOG Removing existing Co-Pilot installed package
powershell -NoProfile -ExecutionPolicy Bypass -Command "$pkg = Get-AppxPackage *Microsoft.Copilot* -ErrorAction SilentlyContinue; if($pkg){$pkg | Remove-AppxPackage}"
call :LOG Deprovisioning standard MS Co-Pilot across device
powershell -command "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like '*Microsoft.Copilot*' | Remove-AppxProvisionedPackage -Online"
powershell -command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -Like '*Microsoft.Copilot*'} | Remove-AppxPackage -AllUsers -ErrorAction Continue"
call :LOG adding keys to ensure it does not get reinstalled by marking device incompatible
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v CopilotDisabledReason /t REG_SZ /d "IsEnabledForGeographicRegionFailed" /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}" /t REG_SZ /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" /v IsUserEligible /t REG_DWORD /d 0 /f

call :LOG Removing Bing Search
powershell -command "Get-AppxPackage | Where-Object DisplayName -like '*Microsoft.BingSearch*' | Remove-AppxPackage"
call :LOG Depovision Bing Search across device
powershell -command "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like '*Microsoft.BingSearch*' | Remove-AppxProvisionedPackage -Online -ErrorAction Continue"

call :LOG Removing Taskbar Widgets that should have died with Vista because now they run an entire chromium browser process
powershell -command "Get-Process *Widget* | Stop-Process"
powershell -command "Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers | Remove-AppxPackage -AllUsers"
powershell -command "Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers | Remove-AppxPackage -AllUsers"
	  
call :LOG Disabling Recall in registry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f

:: ___________________________________________PENDING SECTION START___________________________________________

::optional LMS AMT-vPro Environment disable
::call :LOG Disable LMS1 AKA Intel vPro system
::Stopping and disabling service: LMS
::powershell.exe -NoProfile -Command "$svc = Get-Service LMS -ErrorAction SilentlyContinue; if($svc){  Stop-Service LMS -Force -ErrorAction SilentlyContinue;  Set-Service LMS -StartupType Disabled }"
::Removing service: LMS
::Remove LMS driver packages
::Remove driver package: lms.inf_amd64_3e015d10576493ca
::Remove driver package: lms.inf
::Search for and delete LMS executable files
::No LMS.exe files found in Program Files directories.

::==Remove wasteful Scheduled Tasks==
::Disabling Scheduled Task Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser
::WARNING: Scheduled Task Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser was not Found
::Disabling Scheduled Task Microsoft\Windows\Application Experience\ProgramDataUpdater
::WARNING: Scheduled Task Microsoft\Windows\Application Experience\ProgramDataUpdater was not Found
::Disabling Scheduled Task Microsoft\Windows\Autochk\Proxy
::Disabling Scheduled Task Microsoft\Windows\Customer Experience Improvement Program\Consolidator
::Disabling Scheduled Task Microsoft\Windows\Customer Experience Improvement Program\UsbCeip
::Disabling Scheduled Task Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector
::Disabling Scheduled Task Microsoft\Windows\Feedback\Siuf\DmClient
::Disabling Scheduled Task Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload
::Disabling Scheduled Task Microsoft\Windows\Windows Error Reporting\QueueReporting
::Disabling Scheduled Task Microsoft\Windows\Application Experience\MareBackup
::Disabling Scheduled Task Microsoft\Windows\Application Experience\StartupAppTask
::Disabling Scheduled Task Microsoft\Windows\Application Experience\PcaPatchDbTask
::Disabling Scheduled Task Microsoft\Windows\Maps\MapsUpdateTask


::___________________________________________PENDING SECTION END___________________________________________

:USERTWEAKS
goto UserRegistryDeployment
:: ===============================================================
:: -START SECTION - APPLY PER USER REGISTRY SETTINGS TO ALL USERS
:: ===============================================================

:ApplySettings
call :LOG DEBUG ApplySettings called. Arg1=[%~1]
set "BASE=%~1"
if not defined BASE (
    call :LOG ERROR ApplySettings called with no registry hive
    goto :eof
)
call :LOG Applying settings to %BASE%

:: PER USER REGISTRY KEYS TO APPLY
:: This will loop through the registry settings below and apply them to each loaded user registry hive - %base% is normally HKCU
:: REG ADD "%BASE%\Path" /v ValueName /t REG_DWORD /d 1 /f
::example
::REG ADD "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >nul 2>&1
:: if errorlevel 1 call :Log ERROR setting ValueName for %BASE%


::***********************************************USER HKLM REGISTRY KEYS*******************************************

call :LOG ==================== Begin per-user level tweaks =======================

::echo BASE=%BASE%

call :LOG Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
REG DEL "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f
REG DEL "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /v FolderType /t REG_SZ /d NotSpecified /f

call :LOG Preference- Default Explorer to open at "This PC" as default instead of the quick menu - faster opt --2 is default quick access - and 3 is downloads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f

call :LOG Disabling allowing Windows apps to run in the background systemwide
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f

call :LOG Enabling Game Mode always on which helps further reduce background system resource usage
REG ADD "%BASE%\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f

call :LOG Preference -Enabling end task from Taskbar - super useful to avoid opening task manager just to end a stalled app
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f

call :LOG Preference -Enabling show full right-click context menus in Windows 11
REG ADD "%BASE%\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f

call :LOG Disabling bing search in start menu -keep the start menu local
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

call :LOG Enable allow Pinning more apps on the start menu for less wasted space -such a big start menu
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /d 1 /f

call :LOG Setting speed up menu show delay - Windows default is 400ms - why wait so long
REG ADD "%BASE%\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 10 /f

call :LOG Disabling some gaudi resource consuming desktop visual effects -explorer
call :LOG Setting visual effects setting to custom - other options - default 0 - 1 best appearance - 2 best performance
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAI /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 1 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 1 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d 1 /f
REG ADD "%BASE%\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f
REG ADD "%BASE%\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f
::research this - possible webview dependency removal - found all over the place - runaway webview2.exe processes
::REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v WebView /t REG_DWORD /d 0 /f

::call :LOG Disable transparency effects - optional - left enabled for WindHawk TransparentTB and WallpaperEngine
::REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f 

:advertising
call :LOG Start Disabling User level ads in Windows


call :LOG Disable Explorer search box suggestions -Ads-
REG ADD "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f

call :LOG Disabling file explorer ads
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f

call :LOG Disable reocurring finish setup ads named "Suggest ways to get the most out of Windows"
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f

call :LOG Disabling lock screen tips and ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f

call :LOG Disabling personalized ads
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f

call :LOG Disabling welcome experience ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 0 /f

call :LOG Disabling settings ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f

call :LOG Disabling auto install of suggested apps - "Get more out of windows" ad space
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f

call :LOG Disabling general tips and ads - why are these together Microslop
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f

call :LOG Disabling home screen ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f

call :LOG Disabling Timeline Suggestions ads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f

call :LOG Disable Windows Content Delivery
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v ContentDeliveryAllowed /t REG_DWORD /d 0 /f

call :LOG Disable automatic enabling of OEM and Preinstalled apps
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEnabled /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEverEnabled /t REG_DWORD /d 0 /f

::Windows Diagnostics Feedback request frequency
REG ADD "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f
REG DEL "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /f
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableTailoredExperiencesWithDiagnosticData  /t REG_DWORD /d 1 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" /v EnthusiastMode /t REG_DWORD /d 1 /f

call :LOG Preferrence- Disable the TaskView button in the taskbar - same as "Win+tab" -clutter
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f

call :LOG Preferrence- disable the people button in the taskbar
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" /v PeopleBand /t REG_DWORD /d 0 /f
 
call :LOG Enable right-click menu to auto end tasks from taskbar 
REG ADD "%BASE%\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f

call :LOG disable windows feeds for users
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f
call :LOG Hide the meet now button on the taskbar
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v HideSCAMeetNow /t REG_DWORD /d 1 /f

call :LOG Set the searchbox taskbar to icon only for less wasted space
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f

call :LOG Disabling Bing Search in start menu results
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

call :LOG Disabling start menu ads method 2
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f

call :LOG Disabling tailored experiences with telemitry
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f

call :LOG Disabling Cross-Device Resume -optional but reverse this if you sync your phone to your pc - honestly your web browser should do this - mostly web
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" /v IsResumeAllowed /t REG_DWORD /d 0 /f

call :LOG Disable MS Co-pilot per user registry settings
REG ADD "%BASE%\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot" /v AllowCopilotRuntime /t REG_DWORD /d 0 /f

call :LOG --- Disable Microsoft Office logging
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f

call :LOG --- Disable Microsoft Office client telemetry
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f

call :LOG --- Disable Microsoft Office Customer Experience Improvement Program
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f

call :LOG --- Disable Microsoft Office feedback
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\15.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f
REG ADD "%BASE%\SOFTWARE\Microsoft\Office\16.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f

call :LOG Disabling sticky keys feature because leaving something on the shift-key is just as bad as capslock
REG ADD "%BASE%\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 58 /f

::disabled this section because it negatively affects chips with CCD cache routing -X3d etc- and e-core parking when gaming
::disable game DVR
::add logic to detect if processor has CCD cache before disbling - for now leave as is
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_FSEBehavior /t REG_DWORD /d 2 /f
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 0 /f
::REG ADD "%BASE%\System\GameConfigStore" /v GameDVR_EFSEFeatureFlags /t REG_DWORD /d 0 /f

::Allow RDP remote assistance - leave enabled for business use
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v fAllowToGetHelp /t REG_DWORD /d 0 /f
goto :eof

::***********************************************END of USER REGISTRY SETTINGS TO APPLY***********************************************
:UserRegistryDeployment
call :LOG Starting per-user registry deployment...
call :Log ===== START =====

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :Log Processing loaded user hives
for /f "delims=" %%U in ('reg query HKEY_USERS ^| findstr /R "HKEY_USERS\\S-1-5-21-"') do (
::echo Found User Hive: [%%U]
call :ApplySettings "%%U"
)
:: ================================
:: 2. ALL USER PROFILES
:: ================================
call :Log Processing user profiles (NTUSER.DAT)

for /d %%D in ("C:\Users\*") do (

    set USERNAME=%%~nxD

     ::Skip system profiles
    if /I not "!USERNAME!"=="Public" if /I not "!USERNAME!"=="Default" if /I not "!USERNAME!"=="Default User" (

        if exist "%%D\NTUSER.DAT" (

            call :Log Loading hive for %%D

            reg load HKU\TempHive "%%D\NTUSER.DAT" >nul 2>&1
            if errorlevel 1 (
                call :Log ERROR loading hive for %%D
            ) else (
                call :ApplySettings "HKU\TempHive"

                reg unload HKU\TempHive >nul 2>&1
                if errorlevel 1 (
                   call :Log ERROR unloading hive for %%D
                ) else (
                    call :Log Successfully processed %%D
                )
            )
        )
    )
)

:: ================================
:: 3. DEFAULT PROFILE
:: ================================
call :Log Processing Default profile

if exist "C:\Users\Default\NTUSER.DAT" (

    reg load HKU\DefaultHive "C:\Users\Default\NTUSER.DAT" >nul 2>&1
    if errorlevel 1 (
        call :Log ERROR loading Default profile
    ) else (
       call :ApplySettings "HKU\DefaultHive"

        reg unload HKU\DefaultHive >nul 2>&1
        if errorlevel 1 (
            call :Log ERROR unloading Default profile
        ) else (
            call :Log Default profile updated
        )
    )
) else (
    call :Log Default NTUSER.DAT not found
)

:: ===========================================
:: APPLY REGISTRY SETTINGS TO ALL USERS-END
:: ===========================================
call :Log ===== COMPLETE =====
call :LOG Done. Log file: %LOGFILE%

goto REBOOT
::======================================END FOR EACH USER REGISTRY LOOP==========================================

:GamingTweaks
call :LOG Begin Gaming Tweaks Section

call :LOG Reset and Redetect Windows HPET dependency -High Precision Event Timer- - fixes issue where HPET was not detected properly
bcdedit.exe /deletevalue useplatformclock >nul 2>&1
if errorlevel 1 (
    call :LOG useplatformclock was not explicitly configured or could not be changed.
) else (
    call :LOG Removed explicit useplatformclock override.
)
call :LOG Enabling HAGS - Hardware Accelerated GPU Scheduling - will only work if supported but at least not disabled
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HWSchMode /t REG_DWORD /d 2 /f

call :LOG Enabling Optimizations for Windowed Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR\Graphics" /v OptimizationsForWindowedGames /t REG_DWORD /d 1 /f

call :LOG Increasing system responsiveness for Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v SystemResponsiveness /t REG_DWORD /d 0x0000000a /f

call :LOG Enabling Optimizations for Windowed Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR\Graphics" /v OptimizationsForWindowedGames /t REG_DWORD /d 1 /f

call :LOG Setting GPU priority for Full Screen Apps and Games based on Microsoft Learn Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d Medium /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Latency Sensitive" /t REG_SZ /d True /f

:detectchassisGamingTweaks
	Set "Type=" & For /F EOL^=- %%G In ('
	 %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command
	 "(Get-CimInstance -Query 'Select * From CIM_Chassis').ChassisTypes"^
	 " | Select-Object -Property @{ Label = '-'; Expression = { Switch ($_) {"^
 	" { '3', '4', '5', '6', '7', '13', '15', '16', '24' -Eq $_ } { 'Desktop' };"^
 	" { '8', '9', '10', '11', '12', '14', '18', '21', '30', '31', '32' -Eq $_ } { 'Laptop' };"^
	 " default { '' } } } }" 2^>NUL') Do Set Type=%%G
	If Not Defined Type GoTo unknownchassisgaming
	Set Type
		if /i "%Type%"=="Laptop" goto laptopgaming
		if /i "%Type%"=="Desktop" goto desktopgaming
		goto unknownchassisgaming
	:laptopgaming
		call :LOG Laptop detected - Not recommended to enabled these power tweaks
		::changeme
		goto REBOOT
	:desktopgaming
		call :LOG Desktop detected - Enabling Desktop Only Optimizations
		
		call :LOG Disable power throttling
		REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /t REG_DWORD /d 1 /f
		REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v NoLazyMode /t REG_DWORD /d 00000000 /f
		REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v AlwaysOn /t REG_DWORD /d 00000000 /f

		call :LOG Enable Ultimate performance power plan for desktops only
		powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
		powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61
		::powercfg /getactivescheme
		::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0" /v Attributes /t REG_DWORD /d 2 /f
		::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab\94ac6d29-73ce-41a6-809f-6363ba21b47e" /v Attributes /t REG_DWORD /d 2 /f

		call :LOG Disabling Dynamic P-state for GPUs...forces gpu to run at maximum performance
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$gpuDevices = Get-CimInstance Win32_VideoController | Where-Object {$_.PNPDeviceID -match 'PCI\\VEN_'}; ^
foreach ($gpu in $gpuDevices) { ^
    Write-Host ('Processing GPU: ' + $gpu.Name); ^
    $driverKey = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $gpu.PNPDeviceID) -Name Driver -ErrorAction SilentlyContinue).Driver; ^
    if ($driverKey) { ^
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driverKey; ^
        if (Test-Path $regPath) { ^
            Write-Host ('Setting registry key at: ' + $regPath); ^
            New-ItemProperty -Path $regPath -Name DisableDynamicPstate -PropertyType DWord -Value 1 -Force | Out-Null; ^
            Write-Host 'Dynamic P-state disabled successfully'; ^
        } ^
    } ^
}"

goto REBOOT
	:unknownchassisgaming
		call :LOG Unable to determine chassis type. Skipped power tweaks.
	goto REBOOT
	
:REBOOT



call :LOG ****************************ALL FINISHED!*******************************
call :LOG *																		*
call :LOG *		IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE		*
call :LOG *				 "https://buymeacoffee.com/thebeardofl"					*
call :LOG *																		*
call :LOG ****************************ALL FINISHED!*******************************

call :LOG A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
choice /c YN /n /m "Restart now? [Y/N]: "
if errorlevel 2 goto :EXIT
if errorlevel 1 goto :RESTART

:RESTART
shutdown.exe /r /t 0
exit /b


:EXIT
endlocal
exit
