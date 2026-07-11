	@ECHO OFF
	color f0
	
::script helper objects
::enable extended script logic and variables
setlocal enableextensions enabledelayedexpansion

:: Log stored in current script directory
set "LOGFILE=%~dp0TBOKWinOptimizer.log"

::LOG and echo helper to avoid duplicate lines in script
::usage call :LOG "message"
:LOG 
echo %~1
echo %~1>>"%LOGFILE%"
exit /b
	
::automatically check and get admin rights ::
ECHO Running Admin shell in order to make have permission to make the changes

:CheckPrivileges 
	NET FILE 1>NUL 2>NUL
	if '%errorlevel%' == '0' ( goto gotPrivileges ) else ( goto getPrivileges ) 
:getPrivileges
:: Not elevated, so re-run with elevation
    	powershell -Command "Start-Process cmd -ArgumentList '/c %~s0 %*' -Verb RunAs"
    	exit /b
:gotPrivileges 

cls
TITLE TBOK Windows Performance Optimizer
:Menu
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
ECHO 2. Apply only system level improvements
ECHO 3. Apply only user level improvements
ECHO 4. Apply only gaming tweaks
ECHO 5. EXIT
ECHO.
ECHO ============================================================
CHOICE /c 1234 /n /m "Enter 1-4: (Default: 1 in 10 seconds): " /t 10 /d 1
if errorlevel 4 goto :EXIT
if errorlevel 3 goto :GamingTweaks
if errorlevel 2 goto :UserTweaks
if errorlevel 1 goto :SystemTweaks


:SystemTweaks
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
    
    ECHO Creating restore point...
    PowerShell -ExecutionPolicy Bypass -Command "try { Checkpoint-Computer -Description 'Before TBOK Windows Performance Optimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if !errorlevel! equ 0 (
        ECHO Restore point created successfully.
        call :LOG "Restore point created successfully"
    ) else (
        ECHO WARNING: Could not create restore point.
        ECHO This may be due to:
        ECHO  - A restore point was created in the last 24 hours
        ECHO  - System Protection is disabled for the system drive
        ECHO  - Volume Shadow Copy service issues
        ECHO  - Insufficient disk space
        ECHO.
        ECHO The script can continue without a restore point.
        call :LOG "WARNING: Restore point creation failed"
        pause
    )
) else (
    call :LOG "System Restore disabled - restore point skipped"
)
ECHO.
ECHO Starting selected changes
ECHO.
:Hibernation
ECHO Setting Hibernation Mode based on PC chassis type - should be disabled for desktops - especially with SSD
::	Reasons to leave Hibernation/Fast Startup/Hybrid Shutdown disabled on desktops...
::	1. Most modern PC's come with an SSD or m2 NVME drive and fast startup is not required as it was made to improve performance for systems with slower spinning disks
::	2. Hybrid shutdown/hibernation/fast startup often causes Windows Updates to NOT install properly.
::	3. "system up time" timer in task manager keeps running with this enabled.
::	4. Software with poor memory management design can cause excess ram usage
::	Only Reason to enable on a laptop:
::	Only good thing from Hibernate/Fast Startup is if your Laptop/Tablet battery dies while in sleep/standby mode...
::	your open files are saved because the laptop will wake, save data in ram to hibernation file, then shutdown.
	SetLocal EnableExtensions
:detectchassis
	Set "Type=" & For /F EOL^=- %%G In ('
	 %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command
	 "(Get-CimInstance -Query 'Select * From CIM_Chassis').ChassisTypes"^
	 " | Select-Object -Property @{ Label = '-'; Expression = { Switch ($_) {"^
 	" { '3', '4', '5', '6', '7', '13', '15', '16', '24' -Eq $_ } { 'Desktop' };"^
 	" { '8', '9', '10', '11', '12', '14', '18', '21', '30', '31', '32' -Eq $_ } { 'Laptop' };"^
	 " default { '' } } } }" 2^>NUL') Do Set Type=%%G
	If Not Defined Type GoTo END
	Set Type
		if /i "%Type%"=="Laptop" goto laptop
		if /i "%Type%"=="Desktop" goto desktop
:laptop
	ECHO Laptop detected - enabled hibernation mode
	powercfg -h on
	goto virtualmemory
:desktop
	ECHO Desktop detected - disabled hibernation mode
	powercfg -h off

:virtualmemory
ECHO Optimizing windows virtual memory settings to prevent system hangs on low memory conditions due to SwapFile expansion delay
	::soon to be deprecated WMIC method fallback
	wmic computersystem where name="%computername%" set AutomaticManagedPageFile=False
	wmic pagefileset where name="c:\\pagefile.sys" set InitialSize=8192,MaximumSize=1638
	wmic pagefileset list /format:list
	
	::new powershell method with logic for maximum size following Best Practices
		powershell -NoProfile -Command "$ramMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB); $min = [uint32]8192; $max = [uint32]($ramMB * 2); ^
if ($max -lt $min) { $max = $min }; Set-CimInstance -Query \"SELECT * FROM Win32_ComputerSystem\" -Property @{AutomaticManagedPageFile=$false}; ^
$pf = Get-CimInstance Win32_PageFileSetting -Filter \"Name='C:\\\\pagefile.sys'\"; ^
if ($pf) { ^
    Set-CimInstance -InputObject $pf -Property @{InitialSize=[uint32]$min; MaximumSize=[uint32]$max} ^
} else { ^
    New-CimInstance Win32_PageFileSetting -Property @{Name='C:\\\\pagefile.sys'; InitialSize=[uint32]$min; MaximumSize=[uint32]$max} ^
}; ^
Write-Output \"Configured: RAM=$ramMB MB, Min=$min MB, Max=$max MB\""

	
:Services
ECHO.
ECHO Setting Unecessary Windows Services to Optimized State
ECHO.
ECHO Disabling services that are not used or should be disabled
ECHO.
::AllJoin service not in windows 11pro-ent-ltsc
::sc config AJRouter start=Disabled
sc config AppVClient start=Disabled
sc config NetTcpPortSharing start=Disabled
sc config DialogBlockingService start=Disabled
sc config DiagTrack start=Disabled
sc config UevAgentService start=Disabled
sc config ssh-agent start=Disabled
ECHO.
ECHO Setting non-critical per-use services to manual startup
ECHO Services set to manual allow them to work when needed
ECHO.
sc config ALG start=Manual
sc config AppIDSv start=Manual
sc config AppMgmt start=Manual
sc config AppReadiness start=Manual
sc config Appinfo start=Manual
sc config AssignedAccessManagerSvc start=Manual
sc config AxInstSV start=Manual
sc config BDESVC start=Manual
sc config BcastDVRUserService_* start=Manual
sc config BluetoothUserService_* start=Manual
sc config Browser start=Manual
sc config BTAGService start=Manual
sc config bthserv start=Manual
sc config CaptureService_* start=Manual
sc config cbdhsvc_* start=Manual
sc config CDPSvc start=Manual
sc config CertPropSvc start=Manual
sc config cloudidsvc start=Manual
sc config COMSysApp start=Manual
sc config ClipSVC start=Manual
sc config ConsentUxUserSvc_* start=Manual
sc config CredentialEnrollmentManagerUserSvc_* start=Manual
sc config CscService start=Manual
sc config DcpSvc start=Manual
sc config dcsvc start=Manual
sc config defragsvc start=Manual
sc config DevQueryBroker start=Manual
sc config DeviceAssociationBrokerSvc_* start=Manual
sc config DeviceAssociationService start=Manual
sc config DeviceInstall start=Manual
sc config DevicePickerUserSvc_* start=Manual
sc config DevicesFlowUserSvc_* start=Manual
sc config diagnosticshub.standardcollector.servic start=Manual
sc config diagsvc start=Manual
sc config DisplayEnhancementService start=Manual
sc config DmEnrollmentSvc start=Manual
sc config dmwappushservice start=Manual
sc config dot3svc start=Manual
sc config DoSvc start=Manual
sc config embeddedmode start=Manual
sc config fdPHost start=Manual
sc config fhsvc start=Manual
sc config hidserv start=Manual
sc config icssvc start=Manual
sc config EapHost start=Manual
sc config edgeupdate start=Manual
sc config edgeupdatem start=Manual
sc config EFS start=Manual
sc config EntAppSvc start=Manual
sc config FDResPub start=Manual
sc config Fax start=Manual
sc config FrameServer start=Manual
sc config FrameServerMonitor start=Manual
sc config GraphicsPerfSvc start=Manual
sc config HomeGroupListener start=Manual
sc config HomeGroupProvider start=Manual
sc config HvHost start=Manual
sc config IEEtwCollectorService start=Manual
sc config IKEEXT start=Manual
sc config InstallService start=Manual
sc config IpxlatCfgSvc start=Manual
sc config lfsvc start=Manual
sc config LicenseManager start=Manual
sc config lltdsvc start=Manual
sc config lmhosts start=Manual
sc config LxpSvc start=Manual
sc config McpManagementService start=Manual
sc config MessagingService_* start=Manual
sc config MicrosoftEdgeElevationService start=Manual
sc config MixedRealityOpenXRSvc start=Manual
sc config MSDTC start=Manual
sc config MsKeyboardFilter start=Manual
sc config MSiSCSI start=Manual
sc config msiserver start=Manual
sc config McpManagementService start=Manual
sc config MessagingService_* start=Manual
sc config MicrosoftEdgeElevationService start=Manual
sc config MixedRealityOpenXRSvc start=Manual
sc config MsKeyboardFilter start=Manual
sc config NPSMSvc_* start=Manual
sc config NaturalAuthentication start=Manual
sc config NPSMSvc_* start=Manual
sc config NaturalAuthentication start=Manual
sc config NcaSvc start=Manual
sc config NcbService start=Manual
sc config NcdAutoSetup start=Manual
sc config NetSetupSvc start=Manual
sc config Netman start=Manual
sc config NgcCtnrSvc start=Manual
sc config NgcSvc start=Manual
sc config NlaSvc start=Manual
sc config NcaSvc start=Manual
sc config NcbService start=Manual
sc config NcdAutoSetup start=Manual
sc config NetSetupSvc start=Manual
sc config Netman start=Manual
sc config NgcCtnrSvc start=Manual
sc config NgcSvc start=Manual
sc config NlaSvc start=Manual
sc config netprofm start=Manual
sc config p2pimsvc start=Manual
sc config p2psvc start=Manual
sc config P9RdrService_* start=Manual
sc config PcaSvc start=Manual
sc config PeerDistSvc start=Manual
sc config PenService_* start=Manual
sc config perceptionsimulation start=Manual
sc config PerfHost start=Manual
sc config PhoneSvc start=Manual
sc config PimIndexMaintenanceSvc_* start=Manual
sc config pla start=Manual
sc config PlugPlay start=Manual
sc config PNRPAutoReg start=Manual
sc config PNRPsvc start=Manual
sc config PolicyAgent start=Manual
sc config PrintNotify start=Manual
sc config PrintWorkflowUserSvc_* start=Manual
sc config PushToInstall start=Manual
sc config QWAVE start=Manual
sc config RasAuto start=Manual
sc config RasMan start=Manual
sc config RetailDemo start=Manual
sc config RmSvc start=Manual
sc config RpcLocator start=Manual
sc config SCPolicySvc start=Manual
sc config ScDeviceEnum start=Manual
sc config SCardSvr start=Manual
sc config SDRSVC start=Manual
sc config seclogon start=Manual
sc config SecurityHealthService start=Manual
sc config SEMgrSvc start=Manual
sc config Sense start=Manual
sc config SensorDataService start=Manual
sc config SensorService start=Manual
sc config SensrSvc start=Manual
sc config SessionEnv start=Manual
sc config SharedAccess start=Manual
sc config SharedRealitySvc start=Manual
sc config shpamsvc start=Manual
sc config SmsRouter start=Manual
sc config smphost start=Manual
sc config SNMPTRAP start=Manual
sc config SNMPTrap start=Manual
sc config spectrum start=Manual
sc config SstpSvc start=Manual
sc config SSDPSRV start=Manual
sc config StiSvc start=Manual
sc config StorSvc start=Manual
sc config svsvc start=Manual
sc config swprv start=Manual
::sysmain should be disabled for low ram systems - but benefits mechanical hard drive systems
sc config SysMain start=Manual
sc config TabletInputService start=Manual
sc config TapiSrv start=Manual
sc config TieringEngineService start=Manual
sc config TimeBroker start=Manual
sc config TimeBrokerSvc start=Manual
sc config TokenBroker start=Manual
sc config TroubleshootingSvc start=Manual
sc config TrustedInstaller start=Manual
sc config UI0Detect start=Manual
sc config UdkUserSvc_* start=Manual
sc config UmRdpService start=Manual
sc config UnistoreSvc_* start=Manual
sc config UserDataSvc_* start=Manual
sc config UsoSvc start=Manual
sc config upnphost start=Manual
sc config VacSvc start=Manual
sc config vds start=Manual
sc config vm3dservice start=Manual
sc config vmicguestinterface start=Manual
sc config vmicheartbeat start=Manual
sc config vmickvpexchange start=Manual
sc config vmicrdv start=Manual
sc config vmicshutdown start=Manual
sc config vmictimesync start=Manual
sc config vmicvmsession start=Manual
sc config vmicvss start=Manual
sc config vmvss start=Manual
sc config VSS start=Manual
sc config WaaSMedicSvc start=Manual
sc config WalletService start=Manual
sc config WarpJITSvc start=Manual
sc config wbengine start=Manual
sc config WcsPlugInService start=Manual
sc config wcncsvc start=Manual
sc config WdNisSvc start=Manual
sc config WdiServiceHost start=Manual
sc config WdiSystemHost start=Manual
sc config WebClient start=Manual
sc config webthreatdefsvc start=Manual
sc config Wecsvc start=Manual
sc config wercplsupport start=Manual
sc config WEPHOSTSVC start=Manual
sc config WerSvc start=Manual
sc config WFDSConMgrSvc start=Manual
sc config WiaRpc start=Manual
sc config WinHttpAutoProxySvc start=Manual
sc config WinRM start=Manual
sc config wisvc start=Manual
sc config wlidsvc start=Manual
sc config wlpasvc start=Manual
sc config wmiApSrv start=Manual
sc config WMPNetworkSvc start=Manual
sc config WManSvc start=Manual
sc config WPDBusEnum start=Manual
sc config WpcMonSvc start=Manual
sc config WpnService start=Manual
sc config workfolderssvc start=Manual
sc config WSService start=Manual
sc config XblAuthManager start=Manual
sc config XblGameSave start=Manual
sc config XboxNetApiSvc start=Manual

ECHO.
ECHO Ensuring required services are set to auto State
ECHO This is just in case you used a previous utility that set the services incorrectly
ECHO.
sc config AudioEndpointBuilder start=auto
sc config AudioSrv start=auto
sc config Audiosrv start=auto
sc config BFE start=auto
sc config BITS start=delayed-auto
sc config BrokerInfrastructure start=auto
sc config BthHFSrv start=auto
sc config CDPUserSvc_* start=auto
sc config CoreMessagingRegistrar start=auto
sc config CryptSvc start=auto
sc config DPS start=auto
sc config DcomLaunch start=auto
sc config Dhcp start=auto
sc config DispBrokerDesktopSvc start=auto
sc config Dnscache start=auto
sc config dusmsvc start=auto
sc config EventLog start=auto
sc config EventSystem start=auto
sc config FontCache start=auto
sc config gpsvc start=auto
sc config iphlpsvc start=auto
sc config LSM start=auto
sc config LanmanServer start=auto
sc config LanmanWorkstation start=auto
sc config MapsBroker start=delayed-auto
sc config MpsSvc start=auto
sc config nsi start=auto
sc config OneSyncSvc_* start=auto
sc config Power start=auto
sc config ProfSvc start=auto
sc config RpcEptMapper start=auto
sc config RpcSs start=auto
sc config RemoteAccess start=auto
sc config RemoteRegistry start=auto
sc config SENS start=auto
sc config SamSs start=auto
sc config Schedule start=auto
sc config ShellHWDetection start=auto
sc config Spooler start=auto
sc config sppsvc start=delayed-auto
sc config SystemEventsBroker start=auto
sc config Themes start=auto
sc config tiledatamodelsvc start=auto
sc config TrkWks start=auto
sc config tzautoupdate start=auto
sc config uhssvc start=delayed-auto
sc config UserManager start=auto
sc config VGAuthService start=auto
sc config VMTools start=auto
sc config W32Time start=auto
sc config webthreatdefusersvc_* start=auto
sc config WSearch start=delayed-auto
sc config Wcmsvc start=auto
sc config WinDefend start=auto
sc config Winmgmt start=auto
sc config WlanSvc start=auto
sc config WpnUserService_* start=auto
sc config wscsvc start=delayed-auto
sc config wuauserv start=delayed-auto
sc config wudfsvc start=delayed-auto
sc config XboxGipSvc start=delayed-auto
ECHO Windows Services Changes Completed
ECHO.
ECHO Enabling System-wide Improvements
ECHO.

ECHO Restoring the much beloved F8 Startup menu availability - WHY TF DID THEY REMOVE THAT
::If you have bitlocker enabled - using F8 will prompt you for the recovery key when you use the legacy boot menu
bcdedit /set {default} bootmenupolicy legacy

ECHO Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f
::Set HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\NetworkThrottlingIndex to 4294967295

ECHO Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f

ECHO Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f 

ECHO Increasing system responsiveness for Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v SystemResponsiveness /t REG_DWORD /d 0x0000000a /f

ECHO Speed up shutdown time
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_DWORD /d 1000 /f

ECHO Enabling long file system path support - why is this disabled by default Microsoft
REG ADD "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f

ECHO Turning off telemetry data collection Local Machine
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack /v Start /t REG_DWORD /d 00000004 /f
::next lines possibly eol but have been documented by MS - possibly older telemitry framework
REG ADD "HKLM\SYSTEM\ControlSet001\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /t REG_DWORD /d 0 /f

ECHO GPO option to disable telemetry - Applies to Pro or Enterprise versions only
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 0 /f

ECHO Disabling Wi-Fi Sense through registry
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f

::ECHO Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f

ECHO Enable verbose logon-off status -optional but helpful-
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v VerboseStatus /d 1 REG_DWORD /f

ECHO Disable privacy settings experience - CTT winutil has 0
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE /v DisablePrivacyExperience /t REG_DWORD /d 1 /f

ECHO don't use personalized lock screen with ads - MS Spotlight ads- Default 0
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization /v NoLockScreen /t REG_DWORD /d 1 /f

ECHO =================edge tweaks=================
ECHO Disable Edge so-called start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_WORD /d 0 /f

ECHO Disable exhaustive first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f

::ECHO Disabling gamer mode for Edge so it doesnt monitor your active applications - who uses Edge anyway?
::REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 0 /f

ECHO Disabling submit user feedback because Microsoft does not actually listen - worthless
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f

ECHO Disabling shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f
ECHO ===============end edge tweaks=================

ECHO Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has a known vulnerability
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f
	
::Chris Titus has this listed as one thing, but Microsoft lists it as Windows Protection bit for signed code---conflict	
::ECHO Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 0 /f	

ECHO System level registry tweaks completed
ECHO.

:UserTweaks
ECHO.
ECHO ==================== Begin per-user level tweaks - pending to add apply to all users - for each loop =======================
ECHO.

ECHO Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell /v FolderType /t REG_SZ /d NotSpecified /f

ECHO DISABLE ALLOW WINDOWS APPS TO RUN IN THE BACKGROUND
REG ADD "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f

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
REG ADD "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_DWORD /d 10 /f

ECHO Disabling some gaudi resource consuming desktop visual effects -explorer
ECHO Setting visual effects setting to custom - other options - default 0 - 1 best appearance - 2 best performance
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAI /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 1 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 1 /f
REG ADD "HKCU\Control Panel\Desktop" /v DragFullWindows /t REG_DWORD /d 1 /f
REG ADD "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_DWORD /d 0 /f
REG ADD "HKCU\Control Panel\Keyboard" /v KeyboardDelay /t REG_DWORD /d 0 /f
REG ADD "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f
::research this - possible webview dependency removal
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v WebView /t REG_DWORD /d 0 /f

ECHO Disable transparency effects - optional
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f 

:ADS
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
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
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
::REG ADD "HKCU\SOFTWARE\Microsoft\Siuf\Rules\NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f
::REG DEL "HKCU\SOFTWARE\Microsoft\Siuf\Rules\PeriodInNanoSeconds
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications  /t REG_DWORD /d 1 /f
REG ADD "HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableTailoredExperiencesWithDiagnosticData  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f

REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" /v EnthusiastMode /t REG_DWORD /d 1 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowTaskViewButton /t REG_DWORD /d 1 /f
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" /v PeopleBand /t REG_DWORD /d 0 /f
::REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f
 
REG ADD "HKCU\Control Panel\Desktop" /v AutoEndTasks /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 0 /f
::REG ADD "HKLM\SYSTEM\ControlSet001\Services\Ndu" /v Start /t REG_DWORD /d 2 /f

::REG ADD "HKCU\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v HideSCAMeetNow /t REG_DWORD /d 1 /f
::REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f

::Allow RDP remote assistance
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v fAllowToGetHelp /t REG_DWORD /d 0 /f

ECHO Fixing the Start Menu
ECHO Set the searchbox taskbar to icon only for less wasted space
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f

ECHO Disabling Bing Search in start menu results
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

ECHO Disabling sticky keys feature
REG ADD "HKCU\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_DWORD /d 58 /f

ECHO Disabling start menu ads method 2
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f

ECHO Disabling tailored experiences with telemitry
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f

ECHO Disabling Cross-Device Resume -optional but reverse this if you sync your phone to your pc - honestly your web browser should do this - mostly web
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" /v IsResumeAllowed /t RED_DWORD /d 0

::disable game DVR - negatively affects e-core parking - disabled this section because it negatively affects chips with CCD cache routing
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_FSEBehavior /t REG_DWORD /d 2 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 0 /f
::REG ADD "HKCU\System\GameConfigStore" /v GameDVR_EFSEFeatureFlags /t REG_DWORD /d 0 /f
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f

ECHO ==========================================PENDING==========================================



::DisableLMS1
::Kill LMS process
::Stopping and disabling service: LMS
::sc stop lms
::Removing service: LMS
::Removing LMS driver packages
::Removing driver package: lms.inf_amd64_3e015d10576493ca
::Removing driver package: lms.inf
::Searching and deleting LMS executable files
::No LMS.exe files found in Program Files directories.
::Intel LMS vPro service has been disabled, removed, and blocked.


::==Scheduled Tasks==
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


:: Co-pilot disabling
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot\TurnOffWindowsCopilot to 1
::HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot was not found, Creating...
::Set HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot\TurnOffWindowsCopilot to 1
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowCopilotButton to 0
::HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot was not found, Creating...
::Set HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\IsCopilotAvailable to 0
::Set HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\CopilotDisabledReason to IsEnabledForGeographicRegionFailed
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot\AllowCopilotRuntime to 0
::Set HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked\{CB3B0003-8088-4EDE-8769-8B354AB2FF8C} to
::HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat was not found, Creating...
::Set HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat\IsUserEligible to 0


::Disable Powershell telemitry
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\DisableAIDataAnalysis to 1
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\AllowRecallEnablement to 0
::Set HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState to 0


::Disable Recall

:: ================================
:: LOG FUNCTION
:: ================================
:Log
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
goto :eof

:: ================================
:: APPLY REGISTRY SETTINGS
:: ================================
:ApplySettings
set BASE=%~1

call :Log Applying settings to %BASE%

:: ---- YOUR REGISTRY KEYS HERE ----

reg add "%BASE%\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 call :Log ERROR setting DisableSearchBoxSuggestions for %BASE%

:: ADD MORE KEYS BELOW (copy/paste pattern)
:: reg add "%BASE%\Path" /v ValueName /t REG_DWORD /d 1 /f
:: if errorlevel 1 call :Log ERROR setting ValueName for %BASE%

goto :eof

:: ================================
:: START
:: ================================
echo Starting registry deployment...
call :Log ===== START =====

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :Log Processing loaded user hives

for /f "tokens=1" %%U in ('reg query HKEY_USERS') do (
    echo %%U | findstr /i "_Classes" >nul
    if errorlevel 1 (
        call :ApplySettings "%%U"
    )
)

:: ================================
:: 2. ALL USER PROFILES
:: ================================
call :Log Processing user profiles (NTUSER.DAT)

for /d %%D in ("C:\Users\*") do (

    set USERNAME=%%~nxD

    :: Skip system profiles
    ::if /I not "!USERNAME!"=="Public" if /I not "!USERNAME!"=="Default" if /I not "!USERNAME!"=="Default User" (

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

:: ================================
:: DONE
:: ================================
call :Log ===== COMPLETE =====
echo Done. Log file: %LOGFILE%

endlocal
exit /b
``
ECHO ======================================END PENDING==========================================
=================================
:GamingTweaks
ECHO.
ECHO Begin Gaming Tweaks Section
ECHO.

ECHO Reset and Redetect Windows HPET dependency - fixes rare issue where timer clock was not detected properly
bcdedit /deletevalue useplatformclock

ECHO Enabling HAGS - Hardware Accelerated GPU Scheduling
RED ADD "Computer\HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v "HWSchMode" /t REG_DWORD /d 2 /f

::ECHO Disable power throttling Gaming Tweak only for desktops - this will kill the battery on a laptop
::add detection mechanism for desktop mode or make optional choice to apply anyway.
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v PowerThrottlingOff /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v NoLazyMode /t REG_DWORD /d 00000000 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v AlwaysOn /t REG_DWORD /d 00000000 /f
::same key but add "AlwaysOn"=dword:00000000 and "NoLazyMode"=dword:00000000?

::Enable Ultimate performance power plan for desktops only
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0\Attributes to 2
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab\94ac6d29-73ce-41a6-809f-6363ba21b47e\Attributes  to 2

ECHO Setting GPU priority for Full Screen Apps and Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d Medium /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Latency Sensitive" /t REG_SZ /d True /f
::same key but add "Latency Sensitive"="True"?


================================
endlocal
:REBOOT
ECHO.
ECHO A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
ECHO DO YOU WISH TO REBOOT NOW?
::Add command for Y/N reboot
ECHO.

:EXIT
exit
