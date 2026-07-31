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
    	powershell -Command "Start-Process cmd -ArgumentList '/c %~s0 %*' -Verb RunAs"
    	exit /b
:gotPrivileges 

cls	

::begin script helper objects::
::enable extended script logic and variable holding
setlocal enableextensions enabledelayedexpansion

:: Log stored in current script directory
set "LOGFILE=%~dp0TBOKWinOptimizer.log"

goto menu
::LOG and echo helper to avoid duplicate lines in script
::usage call :LOG "message to echo"
:LOG 
echo(%~1
>>"%LOGFILE%" echo([%DATE% %TIME%] %~1
exit /b

::end script helper objects::


cls
TITLE TBOK Windows Performance Optimizer
:MENU
rundll32.exe cmdext.dll,MessageBeepStub
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
:restorepoint
ECHO Before anything is modified - create system restore point
ECHO Checking if System Restore is enabled...
	reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v RPSessionInterval
	if !errorlevel! equ 0 (
    ECHO System Restore is enabled - checking required services...
    
    :: Check if Volume Shadow Copy service is running
    sc query vss | find "RUNNING"
    if !errorlevel! neq 0 (
        ECHO Starting Volume Shadow Copy service...
        net start vss
        timeout /t 2 /nobreak >nul
    )
    :: Allow creating restore points more frequently than 24 hours
ECHO Ensuring restore point can be created immediately
    reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f
    :: Wait for registry change to take effect
    timeout /t 2 /nobreak >nul
ECHO Enabling system restore feature on system drive
  PowerShell -ExecutionPolicy Bypass -Command "if (-not (Get-ComputerRestorePoint -ErrorAction SilentlyContinue)) {Enable-ComputerRestore -Drive ($env:SystemDrive + '\') }"
ECHO Creating restore point...
    PowerShell -ExecutionPolicy RemoteSigned -Command "try { Checkpoint-Computer -Description 'Status Before TBOK Windows Optimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if !errorlevel! equ 0 (
        ECHO Restore point created successfully.
        ECHO "Restore point created successfully"
    ) else (
        ECHO WARNING: Could not create restore point.
        ECHO This may be due to:
        ECHO  - System Protection is disabled for the system drive
        ECHO  - Volume Shadow Copy service issues
        ECHO  - Insufficient disk space
        ECHO.
        ECHO The script can continue without a restore point but use at your own risk
        ECHO "WARNING: Restore point creation failed"
		ECHO Either continue at your own risk or go manually create a restore point before proceeding
        pause
    )
) else (
    ECHO "System Restore disabled - restore point skipped"
)

ECHO.
ECHO Starting selected changes
ECHO.
:hibernation
ECHO Setting Hibernation Mode based on PC chassis type - should be disabled for desktops - especially with SSD system drives
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
		ECHO Laptop detected - enabled hibernation "fast startup" mode
		powercfg -h on
		goto f8startup
	:desktop
		ECHO Desktop detected - disabled hibernation "fast startup" mode
		powercfg -h off
		goto f8startup
	:unknownchassis
	ECHO Unable to determine chassis type. Hibernation was not changed.
	ECHO.
	
:F8startup
ECHO Restoring the much beloved F8 Startup menu availability - WHY TF DID THEY REMOVE THAT
::Microsoft defaults wants you to power cycle your PC 2 times before giving you options - waste of time
::If you have bitlocker enabled - using F8 will prompt you for the recovery key when you use the legacy boot menu
bcdedit /set {default} bootmenupolicy legacy

:virtualmemory
ECHO Optimizing windows virtual memory settings to prevent system hangs on low memory conditions due to SwapFile expansion delay
ECHO On low ram systems Windows keeps the auto mode current allocation too low IMO - which causes it to fill up and expand too soon and the system lags
ECHO Tests have found that a minimum of 4096 or prefered 8192 is an optimal start - after that it should expand to double the current system ram
ECHO If the system has very little ram though - I recommend setting the max size to 16384
ECHO If your system has more than 64GB of ram - just leave it on auto
	::deprecated WMIC method fallback
	::wmic computersystem where name="%computername%" set AutomaticManagedPageFile=False
	::wmic pagefileset where name="c:\\pagefile.sys" set InitialSize=4096,MaximumSize=16384
	::wmic pagefileset list /format:list
	
	::new powershell method with logic for maximum size following Best Practices
		powershell -NoProfile -Command "$ramMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB); if ($ramMB -ge 65536) { Write-Output \"Skipped: RAM=$ramMB MB (64 GB or more)\"; exit 0 }; $min = [uint32]4096; $max = [uint32]($ramMB * 2); if ($max -lt $min) { $max = $min }; Set-CimInstance -Query \"SELECT * FROM Win32_ComputerSystem\" -Property @{AutomaticManagedPageFile=$false}; $pf = Get-CimInstance Win32_PageFileSetting -Filter \"Name='C:\\\\pagefile.sys'\"; if ($pf) { Set-CimInstance -InputObject $pf -Property @{InitialSize=[uint32]$min; MaximumSize=[uint32]$max} } else { New-CimInstancee='C:\\\\pagefile.sys'; InitialSize=[uint32]$min; MaximumSize=[uint32]$max} }; Write-Output \"Configured: RAM=$ramMB MB, Min=$min MB, Max=$max MB\""
	
:SERVICES
ECHO Update SvHost split process memory Management according to current memory size - works up to around 4TB of RAM
::This changes how many processes are grouped according to available memory - it does not reduce running processes
	for /f %%A in ('powershell -NoProfile -Command "(Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB"') do (set MemoryKB=%%A)
	echo Memory: %MemoryKB% KB
	reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v SvcHostSplitThresholdInKB /t REG_DWORD /d %MemoryKB% /f

ECHO.
ECHO Setting Unecessary Windows Services to Optimized State
ECHO.
ECHO Disabling services that are not used or should be disabled
ECHO.
::AllJoin service not in windows 11pro-ent-ltsc
::sc config AJRouter start= Disabled
sc config AppVClient start= Disabled
sc config NetTcpPortSharing start= Disabled
sc config DialogBlockingService start= Disabled
sc config DiagTrack start= Disabled
sc config UevAgentService start= Disabled
sc config ssh-agent start= Disabled
::sysmain was developed to have the system load commonly used items from mechanical drives into memory for faster processing with less wait
::Findings Rule of thumb - sysmain should be disabled on systems with < 12GB ram - but benefits mechanical hard drive systems with RAM > 12Gb
::sysmain runs on second boot after install and uses about 70-mb ram as a constant process 
::add logic to autodetect and apply - for now disable as a majority benefit on modern systems
::placeholder logic for detecting system disk Type and total memory setting as variables
::if $ram>=12GB and $disktype is SSD or NVME = disable
::if $ram<=12GB and $disktype is SSD or NVME = disable
::if $ram>11GB and $disktopy isNOT SSD NVME = demand
sc config SysMain start= disable

ECHO.
ECHO Setting non-critical per-use services to manual startup so they can still work when needed but are not auto running on startup
ECHO Many of these are manual by default anyway so some of this process is just to restore that behaviour in case something changed them
ECHO.
sc config ALG start= demand
sc config AppIDSvc start= demand
sc config AppMgmt start= demand
sc config AppReadiness start= demand
sc config Appinfo start= demand
sc config AssignedAccessManagerSvc start= demand
sc config AxInstSV start= demand
sc config BDESVC start= demand
::? sc config BcastDVRUserService_* start= demand
::? sc config BluetoothUserService_* start= demand
::x sc config Browser start= demand
sc config BTAGService start= demand
sc config bthserv start= demand
::? sc config CaptureService_* start= demand
::? sc config cbdhsvc_* start= demand
sc config CDPSvc start= demand
sc config CertPropSvc start= demand
sc config cloudidsvc start= demand
sc config COMSysApp start= demand
::d sc config ClipSVC start= demand
::? sc config ConsentUxUserSvc_* start= demand
::? sc config CredentialEnrollmentManagerUserSvc_* start= demand
sc config CscService start= demand
::sc config DcpSvc start= demand
sc config dcsvc start= demand
sc config defragsvc start= demand
sc config DevQueryBroker start= demand
:: old method fails - sc config DeviceAssociationBroker_* start= demand
::new method
powershell.exe -NoProfile -Command "Get-Service -Name 'DeviceAssociationBroker_*' -ErrorAction SilentlyContinue | Set-Service -StartupType Manual"
sc config DeviceAssociationService start= demand
sc config DeviceInstall start= demand
::? sc config DevicePickerUserSvc_* start= demand
::? sc config DevicesFlowUserSvc_* start= demand
::x sc config diagnosticshub.standardcollector.servic start= demand
sc config diagsvc start= demand
sc config DisplayEnhancementService start= demand
sc config DmEnrollmentSvc start= demand
sc config dmwappushservice start= demand
sc config dot3svc start= demand
::d sc config DoSvc start= demand
::d sc config embeddedmode start= demand
sc config fdPHost start= demand
sc config fhsvc start= demand
sc config hidserv start= demand
sc config icssvc start= demand
sc config EapHost start= demand
sc config edgeupdate start= demand
sc config edgeupdatem start= demand
sc config EFS start= demand
::d sc config EntAppSvc start= demand
sc config FDResPub start= demand
::x sc config Fax start= demand
sc config FrameServer start= demand
sc config FrameServerMonitor start= demand
sc config GraphicsPerfSvc start= demand
::x sc config HomeGroupListener start= demand
::x sc config HomeGroupProvider start= demand
sc config HvHost start= demand
::x sc config IEEtwCollectorService start= demand
sc config IKEEXT start= demand
sc config InstallService start= demand
sc config IpxlatCfgSvc start= demand
sc config lfsvc start= demand
sc config LicenseManager start= demand
sc config lltdsvc start= demand
sc config lmhosts start= demand
sc config LxpSvc start= demand
sc config McpManagementService start= demand
::? sc config MessagingService_* start= demand
sc config MicrosoftEdgeElevationService start= demand
::x sc config MixedRealityOpenXRSvc start= demand
sc config MSDTC start= demand
sc config MsKeyboardFilter start= demand
sc config MSiSCSI start= demand
::d sc config msiserver start= demand
::? sc config NPSMSvc_* start= demand
sc config NaturalAuthentication start= demand
sc config NcaSvc start= demand
sc config NcbService start= demand
sc config NcdAutoSetup start= demand
sc config NetSetupSvc start= demand
sc config Netman start= demand
::d sc config NgcCtnrSvc start= demand
::d sc config NgcSvc start= demand
sc config NlaSvc start= demand
sc config netprofm start= demand
::x sc config p2pimsvc start= demand
::x sc config p2psvc start= demand
::? sc config P9RdrService_* start= demand
sc config PcaSvc start= demand
sc config PeerDistSvc start= demand
::? sc config PenService_* start= demand
sc config perceptionsimulation start= demand
sc config PerfHost start= demand
sc config PhoneSvc start= demand
::? sc config PimIndexMaintenanceSvc_* start= demand
sc config pla start= demand
sc config PlugPlay start= demand
::x sc config PNRPAutoReg start= demand
::x sc config PNRPsvc start= demand
sc config PolicyAgent start= demand
sc config PrintNotify start= demand
::? sc config PrintWorkflowUserSvc_* start= demand
sc config PushToInstall start= demand
sc config QWAVE start= demand
sc config RasAuto start= demand
sc config RasMan start= demand
sc config RetailDemo start= demand
sc config RmSvc start= demand
sc config RpcLocator start= demand
sc config SCPolicySvc start= demand
sc config ScDeviceEnum start= demand
sc config SCardSvr start= demand
sc config SDRSVC start= demand
sc config seclogon start= demand
::d sc config SecurityHealthService start= demand
sc config SEMgrSvc start= demand
::d sc config Sense start= demand
sc config SensorDataService start= demand
sc config SensorService start= demand
sc config SensrSvc start= demand
sc config SessionEnv start= demand
sc config SharedAccess start= demand
::x sc config SharedRealitySvc start= demand
sc config shpamsvc start= demand
sc config SmsRouter start= demand
sc config smphost start= demand
sc config SNMPTrap start= demand
::x sc config spectrum start= demand
sc config SstpSvc start= demand
sc config SSDPSRV start= demand
sc config StiSvc start= demand
sc config StorSvc start= demand
sc config svsvc start= demand
sc config swprv start= demand
::sysmain placeholder
::x sc config TabletInputService start= demand
sc config TapiSrv start= demand
sc config TieringEngineService start= demand
::x sc config TimeBroker start= demand
::d sc config TimeBrokerSvc start= demand
sc config TokenBroker start= demand
sc config TroubleshootingSvc start= demand
sc config TrustedInstaller start= demand
::x sc config UI0Detect start= demand
::? sc config UdkUserSvc_* start= demand
sc config UmRdpService start= demand
::? sc config UnistoreSvc_* start= demand
::? sc config UserDataSvc_* start= demand
sc config UsoSvc start= demand
sc config upnphost start= demand
::x sc config VacSvc start= demand
sc config vds start= demand
::x sc config vm3dservice start= demand
sc config vmicguestinterface start= demand
sc config vmicheartbeat start= demand
sc config vmickvpexchange start= demand
sc config vmicrdv start= demand
sc config vmicshutdown start= demand
sc config vmictimesync start= demand
sc config vmicvmsession start= demand
sc config vmicvss start= demand
::x sc config vmvss start= demand
sc config VSS start= demand
::d sc config WaaSMedicSvc start= demand
sc config WalletService start= demand
sc config WarpJITSvc start= demand
sc config wbengine start= demand
::x sc config WcsPlugInService start= demand
sc config wcncsvc start= demand
::d sc config WdNisSvc start= demand
sc config WdiServiceHost start= demand
sc config WdiSystemHost start= demand
sc config WebClient start= demand
sc config webthreatdefsvc start= demand
sc config Wecsvc start= demand
sc config wercplsupport start= demand
sc config WEPHOSTSVC start= demand
sc config WerSvc start= demand
sc config WFDSConMgrSvc start= demand
sc config WiaRpc start= demand
::d sc config WinHttpAutoProxySvc start= demand
sc config WinRM start= demand
sc config wisvc start= demand
sc config wlidsvc start= demand
sc config wlpasvc start= demand
sc config wmiApSrv start= demand
sc config WMPNetworkSvc start= demand
sc config WManSvc start= demand
sc config WPDBusEnum start= demand
sc config WpcMonSvc start= demand
sc config WpnService start= demand
sc config workfolderssvc start= demand
::x sc config WSService start= demand
sc config XblAuthManager start= demand
sc config XblGameSave start= demand
sc config XboxNetApiSvc start= demand

ECHO.
ECHO Ensuring required services are set to auto State
ECHO This is just in case you used a previous utility that set the services incorrectly
ECHO.
sc config AudioEndpointBuilder start= auto
sc config AudioSrv start= auto
::d sc config BFE start= auto
sc config BITS start= delayed-auto
sc config BrokerInfrastructure start= auto
::x sc config BthHFSrv start= auto
::? sc config CDPUserSvc_* start= auto
::d sc config CoreMessagingRegistrar start= auto
sc config CryptSvc start= auto
sc config DPS start= auto
::d sc config DcomLaunch start= auto
sc config Dhcp start= auto
sc config DispBrokerDesktopSvc start= auto
::d sc config Dnscache start= auto
sc config dusmsvc start= auto
sc config EventLog start= auto
sc config EventSystem start= auto
sc config FontCache start= auto
::d sc config gpsvc start= auto
sc config iphlpsvc start= auto
::d sc config LSM start= auto
sc config LanmanServer start= auto
sc config LanmanWorkstation start= auto
::sc config MapsBroker start= delayed-auto
::d sc config MpsSvc start= auto
sc config nsi start= auto
::? sc config OneSyncSvc_* start= auto
sc config Power start= auto
sc config ProfSvc start= auto
::d sc config RpcEptMapper start= auto
::d sc config RpcSs start= auto
::omit sc config RemoteAccess start= auto
::omit sc config RemoteRegistry start= auto
sc config SENS start= auto
sc config SamSs start= auto
::d sc config Schedule start= auto
sc config ShellHWDetection start= auto
sc config Spooler start= auto
::d sc config sppsvc start= delayed-auto
::d sc config SystemEventsBroker start= auto
sc config Themes start= auto
::x sc config tiledatamodelsvc start= auto
sc config TrkWks start= auto
sc config tzautoupdate start= auto
::d sc config uhssvc start= delayed-auto
sc config UserManager start= auto
::x sc config VMTools start= auto
sc config W32Time start= auto
::? sc config webthreatdefusersvc_* start= auto
sc config WSearch start= delayed-auto
sc config Wcmsvc start= auto
::d sc config WinDefend start= auto
sc config Winmgmt start= auto
sc config WlanSvc start= auto
::? sc config WpnUserService_* start= auto
::d sc config wscsvc start= delayed-auto
sc config wuauserv start= delayed-auto
::x sc config wudfsvc start= delayed-auto
sc config XboxGipSvc start= delayed-auto
ECHO.
ECHO Windows Services Changes Completed
ECHO.

:machine-wide-registry
ECHO Enabling System-wide Registry Improvements
ECHO.

ECHO Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f
::alt REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f

ECHO Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f

ECHO Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f 

ECHO Increasing system responsiveness for Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v SystemResponsiveness /t REG_DWORD /d 0x0000000a /f

ECHO Enabling Optimizations for Windowed Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR\Graphics" /v OptimizationsForWindowedGames /t REG_DWORD /d 1 /f

ECHO Speed up shutdown time
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 2000 /f

ECHO Enabling long file system path support - FR though -why is this disabled by default Microsoft
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f

ECHO Disabling the setting that allows hardware to install whatever software it wants - LG Monitor McAffee Incident
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" /v PreventDeviceMetadataFromNetwork /t REG_DWORD /d 1 /f 

ECHO Turning off telemetry data collection Local Machine
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

ECHO Disabling Wi-Fi Sense through registry
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f

::ECHO Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f

ECHO Enable verbose logon-off status on shutdown screen -optional but helpful
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v VerboseStatus /t REG_DWORD /d 1 /f

::this section might not apply - testing needed
ECHO Disable privacy settings experience at first OOBE logon
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v SkipMachineOOBE /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisableVoice /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v Protectyourpc /t REG_DWORD /d 3 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v HideEULAPage /t REG_DWORD /d 1 /f

ECHO Disable the lock screen which includes personalized ads - MS Spotlight ads- Default 0
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f

ECHO =================edge tweaks=================
ECHO Disable Edge so-called start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f

ECHO Disable exhaustive Edge first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f

ECHO Disabling submit user feedback because Microsoft does not actually listen - worthless
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f

ECHO Disabling shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f

::ECHO Disabling gamer mode for Edge so it doesnt monitor your active applications
::ECHO While this serves to lower resource usage for the browser - it also monitors everything running
::REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 0 /f

ECHO ===============end edge tweaks=================

ECHO Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has a known vulnerability
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f
	
ECHO Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f	
REG ADD "HKLM\SYSTEM\ControlSet001\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f
::For system hardening only - sometimes slows shutdown time
::ECHO clear page file at shutdown to remove sensitive memory remnants from pagefile.sys - rebuilds each boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f

ECHO Fix Network Data Usage Graph not working
REG ADD "HKLM\SYSTEM\ControlSet001\Services\Ndu" /v Start /t REG_DWORD /d 2 /f

:systemtelemitry
ECHO ==Disable Windows System Telemetry==
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f

ECHO Disable Powershell telemitry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f
ECHO System level registry tweaks completed
ECHO.


:: =======Disable Microsoft Office telemetry agent==========
echo --- Disable Microsoft Office telemetry agent
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentFallBack`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentFallBack'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentFallBack2016`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentFallBack2016'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentLogOn`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentLogOn'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
:: Disable scheduled task(s): `\Microsoft\Office\OfficeTelemetryAgentLogOn2016`
PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Office\'; $taskNamePattern='OfficeTelemetryAgentLogOn2016'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"

ECHO Remove and Disable Windows Co-pilot -standard- machine wide settings
::Enable reg key that allows app to be uninstalled
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
ECHO Removing existing Co-Pilot installed package
powershell -command "Get-AppxPackage | Where-Object DisplayName -like '*Microsoft.Copilot*' | Remove-AppxPackage"
ECHO Deprovisioning standard MS Co-Pilot across device
powershell -command "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like '*Microsoft.Copilot*' | Remove-AppxProvisionedPackage -Online"
powershell -command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -Like '*Microsoft.Copilot*'} | Remove-AppxPackage -AllUsers -ErrorAction Continue"
ECHO adding keys to ensure it does not get reinstalled by marking device incompatible
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v IsCopilotAvailable /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v CopilotDisabledReason /t REG_SZ /d "IsEnabledForGeographicRegionFailed" /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}" /t REG_SZ /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" /v IsUserEligible /t REG_DWORD /d 0 /f

ECHO Removing Bing Search
powershell -command "Get-AppxPackage | Where-Object DisplayName -like '*Microsoft.BingSearch*' | Remove-AppxPackage"
ECHO Depovision Bing Search across device
powershell -command "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like '*Microsoft.BingSearch*' | Remove-AppxProvisionedPackage -Online -ErrorAction Continue"

ECHO Disabling Recall in registry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f

:: ==========================================PENDING SECTION START==========================================

::DisableLMS1 AKA Intel vPro backdoor system
::Stopping and disabling service: LMS
::sc stop lms
::Removing service: LMS
::Remove LMS driver packages
::Remove driver package: lms.inf_amd64_3e015d10576493ca
::Remove driver package: lms.inf
::Search for and delete LMS executable files
::No LMS.exe files found in Program Files directories.
::Intel LMS vPro service 
::Disable Windows Platform Binary Table backdoor
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f

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

:: ==========================================PENDING SECTION END==========================================

:USERTWEAKS
:: ===============================================================
:: -START SECTION - APPLY PER USER REGISTRY SETTINGS TO ALL USERS
:: ===============================================================
::set BASE=%~1

::call :Log Applying settings to %BASE%

:: PER USER REGISTRY KEYS TO APPLY

::reg add "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >nul 2>&1
::if errorlevel 1 call :Log ERROR setting DisableSearchBoxSuggestions for %BASE%

:: ADD MORE KEYS BELOW (copy/paste pattern)
:: reg add "%BASE%\Path" /v ValueName /t REG_DWORD /d 1 /f
:: if errorlevel 1 call :Log ERROR setting ValueName for %BASE%


::***********************************************USER REGISTRY KEYS*******************************************

ECHO.
ECHO ==================== Begin per-user level tweaks =======================
ECHO =============pending to add apply to all users - for each loop==========
ECHO.

ECHO Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /v FolderType /t REG_SZ /d NotSpecified /f

ECHO DISABLE ALLOW WINDOWS APPS TO RUN IN THE BACKGROUND
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f

ECHO Enabling Game Mode which helps further reduce background system resource usage
REG ADD "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f

ECHO Enabling end task from Taskbar - super useful to avoid opening task manager just to end a stalled app
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f

ECHO Enabling show full right-click context menus in Windows 11
REG ADD "HKCU\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f

ECHO Disable Explorer search box suggestions -Ads-
REG ADD "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f

ECHO Disabling bing search in start menu
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

ECHO Enable allow Pinning more apps on the start menu for less wasted space
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /d 1 /f

ECHO Setting speed up menu show delay - Windows default is 400ms - why wait so long
REG ADD "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 10 /f

ECHO Disabling some gaudi resource consuming desktop visual effects -explorer
ECHO Setting visual effects setting to custom - other options - default 0 - 1 best appearance - 2 best performance
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAI /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f
REG ADD "HKCU\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d 1 /f
REG ADD "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f
REG ADD "HKCU\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f
::research this - possible webview dependency removal - found all over the place - runaway webview2.exe processes
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v WebView /t REG_DWORD /d 0 /f

::ECHO Disable transparency effects - optional
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f 

:advertising
ECHO Start Disabling User level ads in Windows
ECHO.
ECHO Disabling file explorer ads
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f

ECHO Disabling finish setup ads
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f

ECHO Disabling lock screen tips and ads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 0 /f

ECHO Disabling personalized ads
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f

ECHO Disabling welcome experience ads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 0 /f
ECHO Disabling settings ads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f
ECHO Disabling auto install of suggested apps - Get more out of windows ad space
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f
ECHO Disabling general tips and ads - why are these together
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f
ECHO Disabling home screen ads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f
ECHO Disabling Timeline Suggestions ads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f

ECHO ==Disable Windows User Telemetry==
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v ContentDeliveryAllowed /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEnabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEverEnabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f
::Windows Diagnostics Feedback request frequency
REG ADD "HKCU\SOFTWARE\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f
REG DEL "HKCU\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /f
REG ADD "HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableTailoredExperiencesWithDiagnosticData  /t REG_DWORD /d 1 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" /v EnthusiastMode /t REG_DWORD /d 1 /f

ECHO Preferrence- Enable the TaskView button in the taskbar
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 1 /f

ECHO Preferrence- disable the people button in the taskbar
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" /v PeopleBand /t REG_DWORD /d 0 /f

ECHO Preference- Default Explorer to open at "This PC" as default instead of the quick menu - faster opt -- 2 is -default- quick access  and 3 is downloads
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f
 
ECHO Enable right-click menu to auto end tasks from taskbar 
REG ADD "HKCU\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f

ECHO disable windows feeds for users
REG ADD "HKCU\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f
ECHO Hide the meet now button on the taskbar
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v HideSCAMeetNow /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f

ECHO Fixing the Start Menu
ECHO Set the searchbox taskbar to icon only for less wasted space
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f

ECHO Disabling Bing Search in start menu results
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

ECHO Disabling sticky keys feature
REG ADD "HKCU\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 58 /f

ECHO Disabling start menu ads method 2
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f

ECHO Disabling tailored experiences with telemitry
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f

ECHO Disabling Cross-Device Resume -optional but reverse this if you sync your phone to your pc - honestly your web browser should do this - mostly web
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" /v IsResumeAllowed /t REG_DWORD /d 0 /f

ECHO Disable MS Co-pilot per user registry settings
REG ADD "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot" /v AllowCopilotRuntime /t REG_DWORD /d 0 /f

echo --- Disable Microsoft Office logging
reg add "HKCU\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Mail" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\15.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Calendar" /v "EnableCalendarLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\15.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Word\Options" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Policies\Microsoft\Office\15.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Policies\Microsoft\Office\16.0\OSM" /v "EnableUpload" /t REG_DWORD /d 0 /f

echo --- Disable Microsoft Office client telemetry
reg add "HKCU\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "DisableTelemetry" /t REG_DWORD /d 1 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Common\ClientTelemetry" /v "VerboseLogging" /t REG_DWORD /d 0 /f

echo --- Disable Microsoft Office Customer Experience Improvement Program
reg add "HKCU\SOFTWARE\Microsoft\Office\15.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Common" /v "QMEnable" /t REG_DWORD /d 0 /f

echo --- Disable Microsoft Office feedback
reg add "HKCU\SOFTWARE\Microsoft\Office\15.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Office\16.0\Common\Feedback" /v "Enabled" /t REG_DWORD /d 0 /f


::disable game DVR - negatively affects cpu efficiency core parking and cache use on AMD X3d chips
::disabled this section because it negatively affects chips with CCD cache routing -X3d etc- and e-core parking when gaming
::add logic to detect if processor has CCD cache before disbling - for now leave as is
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_FSEBehavior /t REG_DWORD /d 2 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_EFSEFeatureFlags /t REG_DWORD /d 0 /f

::Allow RDP remote assistance - leave enabled for business use
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v fAllowToGetHelp /t REG_DWORD /d 0 /f
::goto :eof


::***********************************************END of USER REGISTRY SETTINGS TO APPLY***********************************************
:: ================================
:: START
:: ================================
::echo Starting registry deployment...
::call :Log ===== START =====

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
::call :Log Processing loaded user hives

::for /f "tokens=1" %%U in ('reg query HKEY_USERS') do (
::    echo %%U | findstr /i "_Classes" >nul
::    if errorlevel 1 (
::        call :ApplySettings "%%U"
::    )
::)

:: ================================
:: 2. ALL USER PROFILES
:: ================================
::call :Log Processing user profiles (NTUSER.DAT)

::for /d %%D in ("C:\Users\*") do (

::    set USERNAME=%%~nxD

    :: Skip system profiles
    ::if /I not "!USERNAME!"=="Public" if /I not "!USERNAME!"=="Default" if /I not "!USERNAME!"=="Default User" (

::        if exist "%%D\NTUSER.DAT" (

::            call :Log Loading hive for %%D

::            reg load HKU\TempHive "%%D\NTUSER.DAT" >nul 2>&1
::            if errorlevel 1 (
::                call :Log ERROR loading hive for %%D
::            ) else (
::                call :ApplySettings "HKU\TempHive"

::                reg unload HKU\TempHive >nul 2>&1
::                if errorlevel 1 (
::                    call :Log ERROR unloading hive for %%D
::                ) else (
::                    call :Log Successfully processed %%D
::                )
::            )
::        )
::    )
::)

:: ================================
:: 3. DEFAULT PROFILE
:: ================================
::call :Log Processing Default profile

::if exist "C:\Users\Default\NTUSER.DAT" (

::    reg load HKU\DefaultHive "C:\Users\Default\NTUSER.DAT" >nul 2>&1
::    if errorlevel 1 (
::        call :Log ERROR loading Default profile
::    ) else (
::       call :ApplySettings "HKU\DefaultHive"

::        reg unload HKU\DefaultHive >nul 2>&1
::        if errorlevel 1 (
::            call :Log ERROR unloading Default profile
::        ) else (
::            call :Log Default profile updated
::        )
::    )
::) else (
::    call :Log Default NTUSER.DAT not found
::)

:: ===========================================
:: APPLY REGISTRY SETTINGS TO ALL USERS-END
:: ===========================================
call :Log ===== COMPLETE =====
echo Done. Log file: %LOGFILE%

goto reboot

ECHO ======================================END PENDING==========================================

:GamingTweaks
ECHO.
ECHO Begin Gaming Tweaks Section
ECHO.

ECHO Reset and Redetect Windows HPET dependency -High Precision Event Timer- - fixes issue where timer HPET clock was not detected properly
bcdedit.exe /deletevalue useplatformclock >nul 2>&1
if errorlevel 1 (
    echo useplatformclock was not explicitly configured or could not be changed.
) else (
    echo Removed explicit useplatformclock override.
)

ECHO Enabling HAGS - Hardware Accelerated GPU Scheduling - will only work if supported but at least not disabled
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HWSchMode /t REG_DWORD /d 2 /f

::ECHO Disable power throttling Gaming Tweak only for desktops - this will kill the battery on a laptop
::add detection mechanism for desktop mode or make optional choice to apply anyway.
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v PowerThrottlingOff /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v NoLazyMode /t REG_DWORD /d 00000000 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v AlwaysOn /t REG_DWORD /d 00000000 /f

::Enable Ultimate performance power plan for desktops only
:: REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0\Attributes to 2
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab\94ac6d29-73ce-41a6-809f-6363ba21b47e\Attributes  to 2

::echo Disabling Dynamic P-state for GPUs...forces gpu to run at 100 and all cores enabled
::powershell -Command "$gpuDevices = Get-WmiObject Win32_VideoController | Where-Object { $_.PNPDeviceID -match 'PCI\\VEN_' }; foreach ($gpu in $gpuDevices) { ::Write-Host 'Processing GPU:' $gpu.Name; $driverKey = (Get-ItemProperty \"HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.PNPDeviceID)\" -Name 'Driver').Driver; if ::($driverKey -match '{.*}') { $regPath = \"HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey\"; Write-Host 'Setting registry key at:' $regPath; ::Set-ItemProperty -Path $regPath -Name 'DisableDynamicPstate' -Value 1 -Type DWord; Write-Host 'Dynamic P-state disabled successfully' } }"

ECHO Setting GPU priority for Full Screen Apps and Games based on Microsoft Learn Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d Medium /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Latency Sensitive" /t REG_SZ /d True /f

::================================
endlocal
:REBOOT
ECHO ***********************
ECHO ****************************ALL FINISHED!*******************************
ECHO *																		*
ECHO *		IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE		*
ECHO *				 "https://buymeacoffee.com/thebeardofl"					*
ECHO *																		*
ECHO ****************************ALL FINISHED!*******************************
ECHO.
ECHO A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
ECHO. 
choice /c YN /n /m "Restart now? [Y/N]: "
if errorlevel 2 goto :EXIT
if errorlevel 1 goto :RESTART

:RESTART
shutdown.exe /r /t 0
exit /b
ECHO.

:EXIT
exit
