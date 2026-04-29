@ECHO OFF
color fA
::Automatically check and get admin rights ::
ECHO Running Admin shell in order to make the changes
:checkPrivileges 
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
ECHO 1. Apply all improvements - except gaming tweaks
ECHO 2. Apply only system level improvements
ECHO 3. Apply only user level improvements
ECHO 4. Apply only gaming tweaks *in development*
ECHO 5. EXIT
ECHO.
ECHO ============================================================
CHOICE /c 1234 /n /m "Enter 1-4: (Default: 1 in 10 seconds): " /t 10 /d 1
if errorlevel 4 goto :exit
if errorlevel 3 goto :gamingtweaks
if errorlevel 2 goto :usertweaks
if errorlevel 1 goto :systemtweaks


:systemtweaks
ECHO.
ECHO Starting selected changes
ECHO.
:hibernation
ECHO Setting Hibernation based on PC chassis type
::	Reasons to leave Hibernation/Fast Startup/Hybrid Shutdown disabled on desktops...
::	1. Most modern PC's come with an SSD or m.2 NVME drive and fast startup is not required.
::	2. Hybrid shutdown/hibernation/fast startup often causes Windows Updates to NOT install properly.
::	3. "system up time" timer in task manager keeps running with this enabled.
::	.
::	1 Reason to enable on a laptop:
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
	goto BadPrintJobs
:desktop
	ECHO Desktop detected - disabled hibernation mode
	powercfg -h off

:services
ECHO.
ECHO Setting Unecessary Windows Services to Optimized State
ECHO.
ECHO Disabling services that are not used or should be disabled
ECHO.
sc config AJRouter start=Disabled
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
::sensor services are traditionally only good for tablet function devices
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
::sysmain should be disabled for low ram systems, but benefits mechanical hard drive systems
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
ECHO Ensuring required services are set to Automatic State
ECHO This is just in case you used a previous utility that set the services incorrectly
ECHO.
sc config AudioEndpointBuilder start=Automatic
sc config AudioSrv start=Automatic
sc config Audiosrv start=Automatic
sc config BFE start=Automatic
sc config BITS start=AutomaticDelayedStart
sc config BrokerInfrastructure start=Automatic
sc config BthHFSrv start=Automatic
sc config CDPUserSvc_* start=Automatic
sc config CoreMessagingRegistrar start=Automatic
sc config CryptSvc start=Automatic
sc config DPS start=Automatic
sc config DcomLaunch start=Automatic
sc config Dhcp start=Automatic
sc config DispBrokerDesktopSvc start=Automatic
sc config Dnscache start=Automatic
sc config dusmsvc start=Automatic
sc config EventLog start=Automatic
sc config EventSystem start=Automatic
sc config FontCache start=Automatic
sc config gpsvc start=Automatic
sc config iphlpsvc start=Automatic
sc config LSM start=Automatic
sc config LanmanServer start=Automatic
sc config LanmanWorkstation start=Automatic
sc config MapsBroker start=AutomaticDelayedStart
sc config MpsSvc start=Automatic
sc config nsi start=Automatic
sc config OneSyncSvc_* start=Automatic
sc config Power start=Automatic
sc config ProfSvc start=Automatic
sc config RpcEptMapper start=Automatic
sc config RpcSs start=Automatic
sc config RemoteAccess start=Automatic
sc config RemoteRegistry start=Automatic
sc config SENS start=Automatic
sc config SamSs start=Automatic
sc config Schedule start=Automatic
sc config ShellHWDetection start=Automatic
sc config Spooler start=Automatic
sc config sppsvc start=AutomaticDelayedStart
sc config SystemEventsBroker start=Automatic
sc config Themes start=Automatic
sc config tiledatamodelsvc start=Automatic
sc config TrkWks start=Automatic
sc config tzautoupdate start=Automatic
sc config uhssvc start=AutomaticDelayedStart
sc config UserManager start=Automatic
sc config VGAuthService start=Automatic
sc config VMTools start=Automatic
sc config W32Time start=Automatic
sc config webthreatdefusersvc_* start=Automatic
sc config WSearch start=AutomaticDelayedStart
sc config Wcmsvc start=Automatic
sc config WinDefend start=Automatic
sc config Winmgmt start=Automatic
sc config WlanSvc start=Automatic
sc config WpnUserService_* start=Automatic
sc config wscsvc start=AutomaticDelayedStart
sc config wuauserv start=AutomaticDelayedStart
sc config wudfsvc start=AutomaticDelayedStart
sc config XboxGipSvc start=AutomaticDelayedStart

ECHO.
ECHO Enabling System Level Improvements for all users
ECHO.

ECHO Optimize system responsiveness
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f 

ECHO Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f

ECHO Increasing system responsiveness
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0x0000000a /f

ECHO Speed up shutdown time
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_DWORD /d 1000 /f
		
ECHO Turn off telemetry data collection
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack /v Start /t REG_DWORD /d 00000004 /f
::next line possibly eol
REG ADD "HKLM\SYSTEM\ControlSet001\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /t REG_DWORD /d 0 /f

::GPO option to disable telemetry - Applies to Pro versions only
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 0 /f

::Disable Wi-Fi Sense
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f

::WAP Push Message Routing Service
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f

::ECHO Enable verbose logon status
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v VerboseStatus /d 1 REG_DWORD /f

::ECHO disable privacy settings experience - CTT winutil has 0
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE /v DisablePrivacyExperience /t REG_DWORD /d 1 /f

::ECHO don't use personalized lock screen - CTT winutil has 0
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization /v NoLockScreen /t REG_DWORD /d 1 /f

ECHO =================edge tweaks=================
ECHO Disable start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_WORD /d 0 /f

ECHO Disable exhaustive first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f

ECHO Disabling gamer mode for Edge
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 0 /f

ECHO Disabling submit user feedback
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f

ECHO Disabling shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f
ECHO =================end edge tweaks=================

ECHO Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f
REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f

ECHO Disable EOL SkyDrive persistent sync - OneDrive replaced but hook still exists
REG ADD "HKLM\software\policies\microsoft\windows\skydrive" /v disablefilesync /t REG_DWORD /d 00000001 /f


:usertweaks
ECHO ==================== Begin user level tweaks =======================

ECHO Speed up FileExplorer browsing and saving files by disabling FolderAutomaticDiscovery
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f
REG DEL "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f
REG ADD "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell /v FolderType /t REG_SZ /d NotSpecified /f

::disable game DVR
::HKCU\System\GameConfigStore |Value: GameDVR_Enabled | GameDVR_FSEBehaviorMode | 
::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR | value
::Set HKCU:\System\GameConfigStore\GameDVR_FSEBehavior to 2
::Set HKCU:\System\GameConfigStore\GameDVR_Enabled to 0
::Set HKCU:\System\GameConfigStore\GameDVR_HonorUserFSEBehaviorMode to 1
::Set HKCU:\System\GameConfigStore\GameDVR_EFSEFeatureFlags to 0
::HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR was not found, Creating...
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR to 0

ECHO Enabling end task from Taskbar - super useful
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f

ECHO Enabling show full right-click context menus in Windows 11
REG ADD "HKCU\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f

ECHO Disable Explorer search box suggestions -Ads-
REG ADD "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f

ECHO Pinning more apps on the start menu for less wasted space
REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /v 1 /f

ECHO Setting speed up menu show delay - Windows default is 400ms wtaf
REG ADD "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_DWORD /d 10

::disable bing search in start menu
::HKCU\Software\Microsoft\Windows\CurrentVersion\Search | Value: BingSearchEnabled | Recommended Value: 0

::disable visual effects -explorer
::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects | Value: VisualFXSetting | Recommended Value: 2

::disable transparency effects
::HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize | Value: EnableTransparency | Suggestion: 0 

==ads=
::disable file explorer ads
::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced | Value: ShowSyncProviderNotifications | Recommended Value: 0

::disable finish setup ads
::HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement | Value: ScoobeSystemSettingEnabled | Recommended Value: 0

::disable lock screen tips and ads
::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager | Value: RotatingLockScreenOverlayEnabled | Recommended Value: 0

::disable personalized ads
::HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo | Value: Enabled | Recommended Value: 0

::disable settings ads
::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager | Value: SubscribedContent-338393Enabled + SubscribedContent-353694Enabled + SubscribedContent-353696Enabled | Recommended Value: 0

::disable start menu ads
::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced | Value: Start_IrisRecommendations | Recommended Value: 0

::disable tailored experiences
::HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy | Value: TailoredExperiencesWithDiagnosticDataEnabled | Recommended Value: 0

::disable general tips and ads
::HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager | Value: SubscribedContent-338389Enabled | Recommended Value: 0

::disable welcome experience ads
::HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager | Value: SubscribedContent-310093Enabled | Recommended Value: 0

::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration\IsResumeAllowed to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDa to 0

::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\SearchboxTaskbarMode to 1
::Set HKCU:\.Default\Control Panel\Keyboard\InitialKeyboardIndicators to 2
::Set HKCU:\Control Panel\Keyboard\InitialKeyboardIndicators to 2
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\BingSearchEnabled to 0
::Set HKCU:\Control Panel\Accessibility\StickyKeys\Flags to 58
::RightClickMenu
::Restarting explorer.exe ...
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\DisableWpbtExecution to 1

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

::==Disable Windows Telemetry==
::Set HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection\AllowTelemetry to 0
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\ContentDeliveryAllowed to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\OemPreInstalledAppsEnabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\PreInstalledAppsEnabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\PreInstalledAppsEverEnabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SilentInstalledAppsEnabled to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338387Enabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338388Enabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338389Enabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-353698Enabled to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SystemPaneSuggestionsEnabled to 0
::HKCU:\SOFTWARE\Microsoft\Siuf\Rules was not found, Creating...
::Set HKCU:\SOFTWARE\Microsoft\Siuf\Rules\NumberOfSIUFInPeriod to 0
::Remove HKCU:\SOFTWARE\Microsoft\Siuf\Rules\PeriodInNanoSeconds

::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection\DoNotShowFeedbackNotifications to 1
::Set HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableTailoredExperiencesWithDiagnosticData to 1
::HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo was not found, Creating...
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy to 1
::Set HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Disabled to 1
::HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config was not found, Creating...
::Set HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config\DODownloadMode to 0
::HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization was not found, Creating...
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization\DODownloadMode to 0
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance\fAllowToGetHelp to 0
::HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager was not found, Creating...
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager\EnthusiastMode to 1
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowTaskViewButton to 0
::HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People was not found, Creating...
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People\PeopleBand to 0
::Set HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\LaunchTo to 1

::Set HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled to 1

::Set HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\SystemResponsiveness to 0
::Set HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\NetworkThrottlingIndex to 4294967295
::Set HKCU:\Control Panel\Desktop\AutoEndTasks to 1
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\ClearPageFileAtShutdown to 0
::Set HKLM:\SYSTEM\ControlSet001\Services\Ndu\Start to 2
::Set HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\IRPStackSize to 30
::HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds was not found, Creating...
::Set HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\ShellFeedsTaskbarViewMode to 2
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\HideSCAMeetNow to 1
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement\ScoobeSystemSettingEnabled to 0

::TweaksTele
::Set HKCU:\Control Panel\Desktop\DragFullWindows to 0
::Set HKCU:\Control Panel\Desktop\MenuShowDelay to 200
::Set HKCU:\Control Panel\Desktop\WindowMetrics\MinAnimate to 0
::Set HKCU:\Control Panel\Keyboard\KeyboardDelay to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ListviewAlphaSelect to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ListviewShadow to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarAnimations to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\VisualFXSetting to 3
::Set HKCU:\Software\Microsoft\Windows\DWM\EnableAeroPeek to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarMn to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDa to 0
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowTaskViewButton to 1
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\SearchboxTaskbarMode to 0

::Display
::EndTaskOnTaskbar
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

::POWERSettings
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0\Attributes to 2
::HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab\94ac6d29-73ce-41a6-809f-6363ba21b47e was not found, Creating...
::Set HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab\94ac6d29-73ce-41a6-809f-6363ba21b47e\Attributes  to 2

Running Script for WPFTweaksPowershell7Tele
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\DisableAIDataAnalysis to 1
::Set HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\AllowRecallEnablement to 0
::Set HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState to 0

::Running Script for WPFTweaksRecallOff
::Disable Recall

::DISABLE ALLOW WINDOWS APPS TO RUN IN THE BACKGROUND
::Set HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\GlobalUserDisabled to 1

=================================
:Gaming
ECHO.
ECHO Begin Gaming Tweaks Section
ECHO.

ECHO Reset and Redetect Windows HPET dependency - fixes rare issue where timer clock was not detected properly
bcdedit /deletevalue useplatformclock

ECHO Disable power throttling (Gaming Tweak)
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v PowerThrottlingOff /t REG_DWORD /d 1 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v NoLazyMode /t REG_DWORD /d 00000000 /f
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling /v AlwaysOn /t REG_DWORD /d 00000000 /f
::same key but add "AlwaysOn"=dword:00000000 and "NoLazyMode"=dword:00000000?

ECHO Setting GPU priority for Full Screen Apps and Games
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d Medium /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f
::REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Latency Sensitive" /t REG_SZ /d True /f
::same key but add "Latency Sensitive"="True"?


================================
:REBOOT
ECHO.
ECHO A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
ECHO DO YOU WISH TO REBOOT NOW?
ECHO.

:EXIT
exit
