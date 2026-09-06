:: Hello - if youre reading this its because you dont just blindly apply scripts willy nilly
:: and you want to know the meat and potatoes of what its doing - no TRUST ME BRO, LOGIC
:: I respect that, and honestly, it's the only way you should run a script you didn't make"
:: This script is a combination of my 25 plus years of IT experience with Windows as an IT admin"
:: While it is nothing slick or polished - it gets down to the essentials that I believe"
:: should be the standard in a Windows Install to function properly
:: The main issue I had with debloat and optimization scripts is that none of them did this
:: Apply the optimizations to all users of a pc and without breaking any features
:: The aim for this is to have a simple script you can either directly run on a pc or
:: push to a machine on the network and have it automatically Optimize the system without you touching anything
:: No GUI no decision just every good change that makes Windows run better and leaner all in one go
:: If you don't understand something here, just ask, my DM's and comments on social media are open
:: If you have an issue or want to request a feature, please request it on GitHub
:: If you want to learn more about each command, use what I use learn.microsoft.com
:: READY... Lets go
:: 
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
	    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
:gotPrivileges 

cls	
::::::::::::begin script helper objects::::::::::
::These are items that are called later in the script to perform a function - trims the code size
::enable extended script logic and variable holding
setlocal enableextensions EnableDelayedExpansion

::Log stored in current script directory with computername info for multi-pc deployments
set "LOGFILE=%~dp0TBOKWinOptimizer-%computername%.log"
goto menu

::This line is called to see if a service exists in the system before making changes - prevents errors
:ServiceExists
sc query "%~1" >nul 2>&1
exit /b %errorlevel%

::This line is called to modify a service startup mode
:SetServiceStartup
powershell.exe -NoProfile -Command ^
"Get-Service -Name '%~1' -ErrorAction SilentlyContinue ^| ForEach-Object { try { sc.exe config ""$($_.Name)"" start= %~2 > $null 2>&1 } catch {} }"
exit /b

::LOG and echo helper to avoid duplicate lines in script - Echoes on screen and also into logfile
::usage call :LOG "message to echo"
:LOG 
echo %*
>>"%LOGFILE%" echo([%DATE% %TIME%] %*
exit /b
::::::::::::end script helper objects::::::::::

:MENU
TITLE TBOK Windows Performance Optimizer V08-28-2026
::MAKE SOUND rundll32.exe cmdext.dll,MessageBeepStub
ECHO _______Welcome to TBOK Windows Performance Optimizer_______
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
ECHO  The Beard of Knowledge Windows Optimizer VERSION 08-28-2026
ECHO.
ECHO Please choose
ECHO 1. Apply system and user level improvements -RECOMMENDED START*Default Autorun*
ECHO 2. Apply only user level improvements
ECHO 3. Apply only gaming tweaks - for desktops only
ECHO 4. EXIT
ECHO.
ECHO IF THIS HELPED YOU OUT -CONSIDER BUYING ME A COFFEE- THATS WHAT POWERED THIS
ECHO "https://buymeacoffee.com/thebeardofl"
ECHO.
ECHO ============================================================
CHOICE /c 1234 /n /m "Enter 1-4: (Default: 1 in 10 seconds): " /t 10 /d 1
if errorlevel 4 goto :EXIT
if errorlevel 3 goto :GamingTweaks
if errorlevel 2 goto :UserTweaks
if errorlevel 1 goto :SystemTweaks



:SYSTEMTWEAKS
ECHO Creating Log file and adding system information
call :LOG Detected:
ver >> "%LOGFILE%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" >> "%LOGFILE%"
PowerShell -c "Get-CimInstance -ClassName Win32_ComputerSystemProduct ^| Select-Object Vendor, Name, IdentifyingNumber" >> "%LOGFILE%"

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
	:RegistryBackup
	call :LOG Creating a separate registry backup in the script folder as a failsafe backup
	reg export HKLM "%~dp0TBOK-OptimizerRegistry-Backup-HKLM.reg" /y >nul
	reg export HKCU "%~dp0TBOK-OptimizerRegistry-Backup-HKCU.reg" /y >nul
	call :LOG Registry backed up and saved to script folder
)
ECHO.
ECHO.
ECHO.
ECHO.
call :LOG Starting selected changes

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
	Set "Type=" & For /F EOL^=- %%G In ('
	 %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command
	 "(Get-CimInstance -Query 'Select * From CIM_Chassis').ChassisTypes"^
	 " | Select-Object -Property @{ Label = '-'; Expression = { Switch ($_) {"^
 	" { '3', '4', '5', '6', '7', '13', '15', '16', '24' -Eq $_ } { 'Desktop' };"^
 	" { '8', '9', '10', '11', '12', '14', '18', '21', '30', '31', '32' -Eq $_ } { 'Laptop' };"^
	 " default { '' } } } }" 2^>NUL') Do Set Type=%%G
	If Not Defined Type GoTo unknownchassis
	ECHO Detecting Chassis Type set by manufacturer
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
	for /f "delims=" %%R in ('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "(Get-CimInstance -Query 'Select * From CIM_Chassis').ChassisTypes -join ','" 2^>NUL') do set "RawChassisType=%%R"
	call :LOG Unable to determine chassis type (raw ChassisTypes=!RawChassisType!). Hibernation was not changed.
	
	
:F8startup
call :LOG Restoring the much beloved F8 Startup menu availability - WHY DID THEY REMOVE THAT
::This is optional to enable but a good default to Restore
::Microsoft default wants you to power cycle your PC 2 times before giving you boot options - waste of time
::If you have bitlocker enabled - using F8 will prompt you for the recovery key when you use the legacy boot menu - be aware
bcdedit /set {default} bootmenupolicy legacy
ECHO.
:virtualmemory
call :LOG Optimizing windows virtual memory settings to prevent system hangs
call :LOG This helps on low memory conditions due to SwapFile expansion delay
:: On low ram systems <16GB - Windows keeps the auto mode current allocation too low IMO
:: This can cause system lag-hang conditions while it expands the swap file because it filled up too soon
:: Tests have found that a minimum of 4096 or prefered 8192 is an optimal start - and max size should be double that up to a point
:: If your system has more than >=32GB of ram - just leave it on auto - Windows does a good job at that size or higher

powershell.exe -NoProfile -Command ^
"try { ^
    $ramMB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 0); ^
    Write-Output ('Detected RAM: ' + $ramMB + ' MB'); ^
    if ($ramMB -ge 32768) { ^
        $cs = Get-WmiObject Win32_ComputerSystem; ^
        if (-not $cs.AutomaticManagedPagefile) { $cs.AutomaticManagedPagefile = $true; $cs.Put() ^| Out-Null }; ^
        Write-Output 'Configured Windows automatic pagefile management.'; ^
        exit 0; ^
    }; ^
    $min = [uint32]4096; ^
    switch ($ramMB) { ^
        {$_ -lt 8192} { $max = [uint32]8192; break }; ^
        {$_ -lt 16384} { $max = [uint32]16384; break }; ^
        default { $max = [uint32]24576 } ^
    }; ^
    $cs = Get-WmiObject Win32_ComputerSystem; ^
    if ($cs.AutomaticManagedPagefile) { $cs.AutomaticManagedPagefile = $false; $cs.Put() ^| Out-Null }; ^
    $pf = Get-WmiObject Win32_PageFileSetting -Filter 'Name=''C:\\pagefile.sys'''; ^
    if ($pf) { ^
        if (($pf.InitialSize -eq $min) -and ($pf.MaximumSize -eq $max)) { ^
            Write-Output ('Already configured. Min=' + $min + ' MB Max=' + $max + ' MB'); ^
            exit 0; ^
        }; ^
        $pf.InitialSize = $min; $pf.MaximumSize = $max; $pf.Put() ^| Out-Null; ^
    } else { ^
        Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name='C:\pagefile.sys'; InitialSize=$min; MaximumSize=$max} ^| Out-Null; ^
    }; ^
    Write-Output ('Configured pagefile: Initial=' + $min + ' MB Maximum=' + $max + ' MB'); ^
    Write-Output 'Reboot required for changes to take effect.'; ^
    exit 0; ^
} catch { ^
    Write-Error $_.Exception.Message; ^
    exit 1; ^
}"
ECHO.	
:SERVICES
call :LOG Enable Modern SvHost split process grouping behaviour according to currently installed RAM
call :LOG This changes the svhost process grouping to an optimized state based on installed RAM
call :LOG Works up to around 4TB of RAM - after that theres no noticeable improvement
::This changes how many processes are grouped according to available memory - it does not actually reduce running processes
	for /f %%A in ('powershell -NoProfile -Command "(Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB"') do (set MemoryKB=%%A)
	call :LOG Installed RAM: !MemoryKB! KB

REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" ^
  /v SvcHostSplitThresholdInKB ^
  /t REG_DWORD ^
  /d !MemoryKB! ^
  /f
ECHO.
ECHO.
call :LOG Setting Unecessary Windows Services to Optimized State

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
::Findings Rule of thumb - sysmain should be disabled on systems with < 12GB ram
::However - it benefits mechanical hard drive systems with > 12Gb RAM

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
ECHO.
call :LOG Done with services to disable
ECHO.
call :LOG Setting non-critical Windows services to manual startup 
call :LOG They still function when needed but are not auto running on startup
call :LOG Many of these are manual by default anyway -FYI
call :LOG Some of this process is just to restore that behaviour in case something changed them
call :SetServiceStartup ALG demand
call :SetServiceStartup AppIDSvc demand
call :SetServiceStartup AppMgmt demand
call :SetServiceStartup AppReadiness demand
call :SetServiceStartup Appinfo demand
call :SetServiceStartup AssignedAccessManagerSvc demand
call :SetServiceStartup AxInstSV demand
call :SetServiceStartup BDESVC demand
call :SetServiceStartup  BcastDVRUserService demand
call :SetServiceStartup  BluetoothUserService demand
::deprecated call :SetServiceStartup 'Browser' demand
call :SetServiceStartup BTAGService demand
call :SetServiceStartup bthserv demand
call :SetServiceStartup  CaptureService demand
call :SetServiceStartup  cbdhsvc demand
::deprecated call :SetServiceStartup CDPSvc demand
call :SetServiceStartup CertPropSvc demand
call :SetServiceStartup cloudidsvc demand
call :SetServiceStartup COMSysApp demand
call :SetServiceStartup  ClipSVC demand
call :SetServiceStartup  ConsentUxUserSvc demand
call :SetServiceStartup  CredentialEnrollmentManagerUserSvc demand
call :SetServiceStartup CscService demand
call :SetServiceStartup  DcpSvc demand
call :SetServiceStartup dcsvc demand
call :SetServiceStartup defragsvc demand
call :SetServiceStartup DevQueryBroker demand
call :SetServiceStartup  DeviceAssociationBroker demand
call :SetServiceStartup DeviceAssociationService demand
call :SetServiceStartup DeviceInstall demand
call :SetServiceStartup  DevicePickerUserSvc demand
call :SetServiceStartup  DevicesFlowUserSvc demand
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
call :SetServiceStartup  MessagingService demand
call :SetServiceStartup MicrosoftEdgeElevationService demand
call :SetServiceStartup  MixedRealityOpenXRSvc demand
call :SetServiceStartup MSDTC demand
call :SetServiceStartup MsKeyboardFilter demand
call :SetServiceStartup MSiSCSI demand
call :SetServiceStartup  msiserver demand
call :SetServiceStartup  NPSMSvc demand
call :SetServiceStartup NaturalAuthentication demand
call :SetServiceStartup NcaSvc demand
call :SetServiceStartup NcbService demand
call :SetServiceStartup NcdAutoSetup demand
call :SetServiceStartup NetSetupSvc demand
call :SetServiceStartup Netman demand
call :SetServiceStartup  NgcCtnrSvc demand
call :SetServiceStartup  NgcSvc demand
::omitforENTERPRISE call :SetServiceStartup NlaSvc demand
::omitforENTERPRISE call :SetServiceStartup netprofm demand
call :SetServiceStartup  p2pimsvc demand
call :SetServiceStartup  p2psvc demand
call :SetServiceStartup  P9RdrService demand
call :SetServiceStartup PcaSvc demand
call :SetServiceStartup PeerDistSvc demand
call :SetServiceStartup  PenService demand
call :SetServiceStartup perceptionsimulation demand
call :SetServiceStartup PerfHost demand
call :SetServiceStartup PhoneSvc demand
call :SetServiceStartup  PimIndexMaintenanceSvc demand
call :SetServiceStartup pla demand
call :SetServiceStartup PlugPlay demand
call :SetServiceStartup  PNRPAutoReg demand
call :SetServiceStartup  PNRPsvc demand
call :SetServiceStartup PolicyAgent demand
call :SetServiceStartup PrintNotify demand
call :SetServiceStartup  PrintWorkflowUserSvc demand
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
::omitforENTERPRISE call :SetServiceStartup TokenBroker demand
call :SetServiceStartup TroubleshootingSvc demand
call :SetServiceStartup  UI0Detect demand
call :SetServiceStartup  UdkUserSvc demand
call :SetServiceStartup UmRdpService demand
call :SetServiceStartup  UnistoreSvc demand
call :SetServiceStartup  UserDataSvc demand
::omitforENTERPRISE call :SetServiceStartup UsoSvc demand
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
::omitforENTERPRISE call :SetServiceStartup WpnService demand
call :SetServiceStartup workfolderssvc demand
::deprecated call :SetServiceStartup  WSService demand
call :SetServiceStartup XblAuthManager demand
call :SetServiceStartup XblGameSave demand
call :SetServiceStartup XboxNetApiSvc demand
ECHO.
call :LOG Done with manual services
ECHO.
call :LOG Ensuring required services are set to automatic State
call :LOG This is just in case you used a previous utility that set the services incorrectly
call :SetServiceStartup AudioEndpointBuilder auto
call :SetServiceStartup AudioSrv auto
call :SetServiceStartup BFE auto
call :SetServiceStartup BITS auto
call :SetServiceStartup BrokerInfrastructure auto
call :SetServiceStartup BthHFSrv auto
call :SetServiceStartup CDPUserSvc auto
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
call :SetServiceStartup OneSyncSvc auto
call :SetServiceStartup Power auto
call :SetServiceStartup ProfSvc auto
call :SetServiceStartup RpcEptMapper auto
call :SetServiceStartup RpcSs auto
::omitforENTERPRISE call :SetServiceStartup RemoteAccess auto
::omitforENTERPRISE call :SetServiceStartup RemoteRegistry auto
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
call :SetServiceStartup WpnUserService auto
ECHO.
Call :LOG Changing less essential services to delayed-auto
::omit call :SetServiceStartup MapsBroker delayed-auto
call :SetServiceStartup SecurityHealthService delayed-auto
call :SetServiceStartup WSearch delayed-auto
call :SetServiceStartup wscsvc delayed-auto
call :SetServiceStartup wuauserv delayed-auto
call :SetServiceStartup wudfsvc delayed-auto
call :SetServiceStartup XboxGipSvc delayed-auto
ECHO.
call :LOG Windows Services Changes Completed
ECHO.
ECHO.
:machine-wide-registry
call :LOG Enabling System-wide Registry Improvements

call :LOG Disabling network throttling
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f

call :LOG Fixing IRP stack size for better network flow - MS default is 15 for 10mbps - do not set above 32 for stability
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f

call :LOG Optimize system responsiveness - 10 is optimal - setting to 0 actually clamps it to 20 - Microsoft Docs
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f 

call :LOG Speed up shutdown time
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 5000 /f
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 5000 /f

call :LOG Enabling long file system path support -why is this disabled by default Microsoft
::Enable in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
::Enable for last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f

call :LOG Disabling the setting allowing hardware to install whatever software addon - LG Monitor McAffee Incident
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" /v PreventDeviceMetadataFromNetwork /t REG_DWORD /d 1 /f 

call :LOG Disable Webview dependency for Search - breaks nothing - puts search back into classic mode
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledState /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledStateOptions /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v Variant /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayload /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayloadKind  /t REG_DWORD /d 0 /f
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledState /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v EnabledStateOptions /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v Variant /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayload /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260" /v VariantPayloadKind  /t REG_DWORD /d 0 /f

call :LOG Turning off telemetry data collection Local Machine
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowDesktopAnalyticsProcessing /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v DiagTrack /t REG_DWORD /d 0 /f
REG ADD "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v LimitEnhancedDiagnosticDataWindowsAnalytics /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\WMI\AutoLogger\Diagtrack-Listener" /v Start /t REG_DWORD /d 0 /f
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /v Start /t REG_DWORD /d 00000004 /f


call :LOG Enable verbose logon-off status on shutdown screen -optional but helpful
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v VerboseStatus /t REG_DWORD /d 1 /f

::Control OOBE experience for new users or major updates-testing needed to confirm but it is documented
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

call :LOG Disabling Windows Platform Binary Table that allows vendors to execute programs at boot
::disables it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f	
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f
::disables it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Control\Session Manager" /v DisableWpbtExecution /t REG_DWORD /d 1 /f
REG ADD "HKLM\SYSTEM\ControlSet001\Control\FirmwareResources" /v WPBT /t REG_BINARY /d 0 /f


call :LOG Fix Network Data Usage Graph not working
::Fixes it in last known good config
REG ADD "HKLM\SYSTEM\ControlSet001\Services\Ndu" /v Start /t REG_DWORD /d 2 /f
::Fixes it in current config
REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 2 /f

:systemtelemitry
call :LOG Disabling Windows System Telemetry through
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled  /t REG_DWORD /d 1 /f
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f

call :LOG Disable Powershell telemitry
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f

:EdgeTweaks
call :LOG Disabling MS Edge Automatic Background Startup
call :LOG Disable Edge so-called start boost - Edge runs on startup even if you dont use it
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f

call :LOG Disable MS Edge from running in the background after close
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f

call :LOG Disable MS Edge exhaustive Edge first run experience
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f

call :LOG Disabling MS Edge submit user feedback
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v UserFeedbackAllowed /t REG_DWORD /d 0 /f

call :LOG Disabling MS Edge shopping assistant ads
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f

call :LOG Enabling MS Edge PC gaming mode for lower CPU usage while Gaming
::While this serves to lower CPU resource usage for the browser - it also monitors everything running
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v GamerModeEnabled /t REG_DWORD /d 1 /f

call :LOG Disable MS Edge Sending Browser Usage DiagnosticData 0
REG ADD "HKLM\Software\Policies\Microsoft\Edge" /v DiagnosticData /t REG_DWORD /d 0 /f

call :LOG Disabling Microsoft Recall from being enabled
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f

::call :LOG Wi-Fi Sense Disable affects devices autoconnecting - leaving enabled
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisensecredshared /t REG_DWORD /d 0 /f
::REG ADD "HKLM\software\microsoft\wcmsvc\wifinetworkmanager" /v wifisenseopen /t REG_DWORD /d 0 /f

::call :LOG Disable WAP Push Message Routing Service - Found Required for Enterprise MDM - excluding
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" /v start /t REG_DWORD /d 00000004 /f

::call :LOG Disabling Windows Defender sample reporting - sends all scanned unknown files to Microsoft and has a known vulnerability
::Microsoft protected these keys from being modified in an update
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v spynetreporting /t REG_DWORD /d 0 /f
::REG ADD "HKLM\software\microsoft\windows defender\spynet" /v submitsamplesconsent /t REG_DWORD /d 0 /f

::Optional For system hardening only - Clear pagefile at shutdown
:: sometimes slows shutdown time removing sensitive memory remnants from pagefile.sys - rebuilds each boot
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f

::call :LOG Disable GameDVR - not recommended on AMD X3d chips due to CCD cache routing
::REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR /t REG_DWORD /d 0 /f
::REG ADD "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement" /v AllowGameDVR /t REG_DWORD /d 0 /f

::Disable Windows Code Integrity app control - SmartAPPControl
::REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f

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

call :LOG System level registry tweaks completed
ECHO.
ECHO.
call :LOG Time for some bloat removal
ECHO.
call :LOG Remove and Disable Windows Co-pilot -standard version- machine wide
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
:PowerShell -ExecutionPolicy Unrestricted -Command "$taskPathPattern='\Microsoft\Windows\'; $taskNamePattern='Microsoft Compatibility Appraiser Exp'; Write-Output "^""Disabling tasks matching pattern `"^""$taskNamePattern`"^""."^""; $tasks = @(Get-ScheduledTask -TaskPath $taskPathPattern -TaskName $taskNamePattern -ErrorAction Ignore); if (-Not $tasks) {; Write-Output "^""Skipping, no tasks matching pattern `"^""$taskNamePattern`"^"" found, no action needed."^""; exit 0; }; $operationFailed = $false; foreach ($task in $tasks) {; $taskName = $task.TaskName; if ($task.State -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.StateEnum]::Disabled) {; Write-Output "^""Skipping, task `"^""$taskName`"^"" is already disabled, no action needed."^""; continue; }; try {; $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Output "^""Successfully disabled task `"^""$taskName`"^""."^""; } catch {; Write-Error "^""Failed to disable task `"^""$taskName`"^"": $($_.Exception.Message)"^""; $operationFailed = $true; }; }; if ($operationFailed) {; Write-Output 'Failed to disable some tasks. Check error messages above.'; exit 1; }"
::Disabling Scheduled Task Microsoft\Windows\Application Experience\ProgramDataUpdater
::Disabling Scheduled Task Microsoft\Windows\Application Experience\MareBackup
::Disabling Scheduled Task Microsoft\Windows\Application Experience\StartupAppTask
::Disabling Scheduled Task Microsoft\Windows\Application Experience\PcaPatchDbTask
::Disabling Scheduled Task Microsoft\Windows\Autochk\Proxy
::Disabling Scheduled Task Microsoft\Windows\Customer Experience Improvement Program\Consolidator
::Disabling Scheduled Task Microsoft\Windows\Customer Experience Improvement Program\UsbCeip
::Disabling Scheduled Task Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector
::Disabling Scheduled Task Microsoft\Windows\Feedback\Siuf\DmClient
::Disabling Scheduled Task Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload
::Disabling Scheduled Task Microsoft\Windows\Maps\MapsUpdateTask
::Disabling Scheduled Task Microsoft\Windows\Windows Error Reporting\QueueReporting

::___________________________________________PENDING SECTION END___________________________________________

:USERTWEAKS
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
:ApplySettings

call :LOG ========= Apply Tweaks to User Registry Hives and Default ==============

call :LOG DEBUG ApplySettings called. Arg1=[%~1]
set "BASE=%~1"
if not defined BASE (
    call :LOG ERROR ApplySettings called with no registry hive
    goto :eof
)

call :LOG Applying settings to %BASE%

::***********************************************USER HKCU REGISTRY KEYS*******************************************

call :LOG Speed up FileExplorer browsing and saving files by disabling Folder auto Discovery
REG DELETE "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" /f
REG DELETE "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" /f
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /f
REG ADD "%BASE%\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" /v FolderType /t REG_SZ /d NotSpecified /f

call :LOG Preference- Default Explorer to open at "This PC" as default instead of the quick menu
::--1 - fastest load --2 is default quick access - and 3 is downloads
REG ADD "%BASE%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f

call :LOG Disabling allowing Windows apps to run in the background systemwide
REG ADD "%BASE%\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f

call :LOG Enabling Game Mode always on which helps further reduce background system resource usage
::uses ~14mb ram but helps Processors with CCD technology and e-core parking
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
call :LOG Setting visual effects setting to custom
:: 3 is custom - default 0 - 1 best appearance - 2 best performance but takes windows look to 1990
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
REG DELETE "%BASE%\SOFTWARE\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /f
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

::********************************END of USER REGISTRY SETTINGS TO APPLY********************************
:UserRegistryDeployment
call :LOG Starting per-user registry deployment...

:: ================================
:: 1. CURRENTLY LOADED USERS
:: ================================
call :Log Processing loaded user hives
for /f "delims=" %%U in ('reg query HKEY_USERS ^| findstr /R "HKEY_USERS\\S-1-5-21- HKEY_USERS\\S-1-12-1-"') do (
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
call :LOG ****************************ALL FINISHED!******************************
call :LOG .
call :LOG .    IF THIS SCRIPT HELPED YOU OUT - CONSIDER BUYING ME A COFFEE
call :LOG .         "https://buymeacoffee.com/thebeardofl"
call :LOG .
call :LOG ****************************ALL FINISHED!******************************

call :LOG A REBOOT IS HIGHLY RECOMMENDED FOR ALL THE SETTINGS TO APPLY PROPERLY
choice /c YN /n /m "Restart now? [Y/N]: Default N in 10 seconds " /t 10 /d 2
if errorlevel 2 goto :EXIT
if errorlevel 1 goto :RESTART

:RESTART
shutdown.exe /r /t 0
exit /b

:EXIT
endlocal
exit
