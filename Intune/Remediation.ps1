#Requires -RunAsAdministrator
<#
Intune Proactive Remediation - portage du script batch "TBOK Windows Performance Optimizer".
Profil de defaut : parc d'entreprise (bureautique). Bascule les $Config ci-dessous pour
activer les sections desactivees par defaut (telemetrie, boot legacy, gaming).
Pas de section retrait Copilot : l'org utilise Copilot 365 (M365 Copilot dans les apps
Office), independant du Copilot consumer integre a l'OS - rien a nettoyer ici.
Intune : configurer "Run this script using the logged-on credentials" = No (execution SYSTEM),
"Enforce script signature check" selon ta politique, 64-bit PowerShell = Yes.
#>

$ScriptVersion = '1.2.0'
$MarkerPath    = 'HKLM:\SOFTWARE\TBOK-Optimizer'
$LogDir        = "$env:ProgramData\TBOK-Optimizer"
$LogFile       = Join-Path $LogDir 'remediation.log'

$Config = @{
    CreateRestorePoint        = $true
    ApplyPerformanceTweaks    = $true    # pagefile, network throttling, IRPStackSize, SvcHostSplit, shutdown timeout, long paths
    ApplyServiceStartupTweaks = $true    # listes demand/auto/delayed-auto ci-dessous
    ConfigureHibernation      = $true    # desktop -> off, laptop -> on, chassis indetermine -> on ne touche a rien
    DisableSshAgentService    = $false   # laisse a false si des postes dev sont dans le groupe cible
    DisableConsumerFeatures   = $false   # pubs Start/Explorer, suggestions - cosmetique, pas lie a la telemetrie
    SetLegacyBootMenu         = $false   # bcdedit F8 legacy - modifie le comportement de recuperation BitLocker
    ApplyGamingTweaks         = $false   # HAGS seulement (le plan Ultimate Performance / lock P-state GPU ne sont pas portes)
    ApplyUserPreferenceTweaks = $true    # prefs Explorer par profil (This PC par defaut, End Task, menu contextuel complet)
}

# Telemetrie : toggles individuels plutot qu'un flag global "tout ou rien".
# - Les 4 premiers sont purement cosmetiques (pubs/suggestions/feedback), zero impact outillage.
# - Les 4 suivants sont desactives par defaut : ils peuvent degrader Defender for Endpoint,
#   Update Compliance / Windows Update for Business, ou la capacite de support interne
#   (dumps locaux). A activer seulement apres validation avec l'equipe securite/infra.
$Config.Telemetry = @{
    DisableFeedbackNotifications = $true    # popups "notez cette app" - cosmetique
    DisableAdvertisingId         = $true    # pub personnalisee - cosmetique
    LimitEnhancedDiagnosticData  = $true    # recommande par Microsoft pour les orgs utilisant Desktop/Endpoint Analytics
    DisableRecall                = $true    # durcissement securite largement recommande, indep. de la telemetrie generale
    LowerTelemetryLevel          = $false   # AllowTelemetry=0 (Security) -- peut degrader Defender for Endpoint / Update Compliance
    DisableDiagTrackService      = $false   # coupe TOUTE remontee de diagnostic -- meme risque que ci-dessus
    DisableWindowsErrorReporting = $false   # reduit la capacite de support interne (dumps locaux)
    DisableDeliveryOptimization  = $false   # pas de la telemetrie : impacte le P2P de distribution des mises a jour sur le LAN, generalement deconseille sur un parc
}

New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line
}

function Invoke-Safely {
    param([string]$Description, [scriptblock]$Action)
    try {
        & $Action
        Write-Log "OK: $Description"
        return $true
    } catch {
        Write-Log "FAILED: $Description -- $($_.Exception.Message)"
        return $false
    }
}

function Set-ServiceStartupSafely {
    param(
        [string]$Name,
        [ValidateSet('Automatic', 'Manual', 'Disabled', 'DelayedAutomatic')]
        [string]$StartupType
    )
    $services = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $services) { return }
    foreach ($svc in $services) {
        try {
            if ($StartupType -eq 'DelayedAutomatic') {
                $null = sc.exe config $svc.Name start= delayed-auto
                if ($LASTEXITCODE -ne 0) { throw "sc.exe exited $LASTEXITCODE" }
            } else {
                Set-Service -Name $svc.Name -StartupType $StartupType -ErrorAction Stop
            }
            Write-Log "OK: service $($svc.Name) -> $StartupType"
        } catch {
            Write-Log "FAILED: service $($svc.Name) -> $StartupType -- $($_.Exception.Message)"
        }
    }
}

$RebootRequired = $false
Write-Log "=== Remediation started (v$ScriptVersion) ==="

# --- Point de restauration (avec repli backup registre si echec) ---
if ($Config.CreateRestorePoint) {
    Invoke-Safely "Enable System Restore on system drive" {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
    }
    Invoke-Safely "Ensure VSS service is running" {
        if ((Get-Service -Name VSS).Status -ne 'Running') { Start-Service VSS -ErrorAction Stop }
    }
    Invoke-Safely "Allow immediate restore point creation" {
        New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
            -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
    }
    $rpOk = Invoke-Safely "Create restore point 'Before Intune Optimizer Remediation'" {
        Checkpoint-Computer -Description 'Before Intune Optimizer Remediation' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }
    if (-not $rpOk) {
        Invoke-Safely "Fallback: export HKLM/HKCU registry backup" {
            reg export HKLM (Join-Path $LogDir 'HKLM-backup.reg') /y | Out-Null
            reg export HKCU (Join-Path $LogDir 'HKCU-backup.reg') /y | Out-Null
        }
    }
}

# --- Hibernation selon le type de chassis (repli sur "ne rien changer" si indetermine) ---
if ($Config.ConfigureHibernation) {
    $chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes
    $desktopTypes = 3, 4, 5, 6, 7, 13, 15, 16, 24
    $laptopTypes  = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    if ($chassisTypes | Where-Object { $_ -in $desktopTypes }) {
        Invoke-Safely "Disable hibernation (desktop, chassis=$($chassisTypes -join ','))" { powercfg -h off }
    } elseif ($chassisTypes | Where-Object { $_ -in $laptopTypes }) {
        Invoke-Safely "Enable hibernation (laptop, chassis=$($chassisTypes -join ','))" { powercfg -h on }
    } else {
        Write-Log "SKIPPED: chassis type undetermined (raw=$($chassisTypes -join ',')) - hibernation left unchanged"
    }
}

# --- Tweaks de performance ---
if ($Config.ApplyPerformanceTweaks) {

    Invoke-Safely "Disable network throttling" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
            -Name NetworkThrottlingIndex -PropertyType DWord -Value 0xffffffff -Force | Out-Null
    }
    Invoke-Safely "Set SystemResponsiveness to 10" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
            -Name SystemResponsiveness -PropertyType DWord -Value 10 -Force | Out-Null
    }
    Invoke-Safely "Speed up service shutdown timeout" {
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' `
            -Name WaitToKillServiceTimeout -PropertyType String -Value '5000' -Force | Out-Null
    }
    Invoke-Safely "Enable long path support" {
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
            -Name LongPathsEnabled -PropertyType DWord -Value 1 -Force | Out-Null
    }
    Invoke-Safely "Set SvcHost split threshold to installed RAM" {
        $memKB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' `
            -Name SvcHostSplitThresholdInKB -PropertyType DWord -Value ([uint32]$memKB) -Force | Out-Null
    }

    # Set-CimInstance sur Win32_PageFileSetting renvoie "Valeur hors de la plage" sur pas mal de
    # builds (round-trip de proprietes read-only cote provider). Get-WmiObject/.Put() evite le
    # faux succes (l'exception devient catchable), mais peut encore echouer sur certaines
    # machines si InitialSize et MaximumSize sont pousses dans le meme .Put() - certains
    # providers WMI valident les deux valeurs contre un etat pas encore rafraichi. On les
    # pousse donc en 2 appels separes (contournement documente), avec un log de l'etat courant
    # a chaque etape pour pouvoir diagnostiquer precisement laquelle echoue si ca persiste.
    $ramMB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 0)
    if ($ramMB -ge 32768) {
        Invoke-Safely "Set pagefile management to automatic (RAM=$ramMB MB >= 32GB)" {
            $cs = Get-WmiObject Win32_ComputerSystem
            if (-not $cs.AutomaticManagedPagefile) {
                $cs.AutomaticManagedPagefile = $true
                $cs.Put() | Out-Null
                $script:RebootRequired = $true
            }
        }
    } else {
        $min = 4096
        $max = if ($ramMB -lt 8192) { 8192 } elseif ($ramMB -lt 16384) { 16384 } else { 24576 }
        Write-Log "Pagefile target: RAM=$ramMB MB, Initial=$min MB Maximum=$max MB"

        Invoke-Safely "Disable automatic pagefile management" {
            $cs = Get-WmiObject Win32_ComputerSystem
            Write-Log "AutomaticManagedPagefile currently=$($cs.AutomaticManagedPagefile)"
            if ($cs.AutomaticManagedPagefile) {
                $cs.AutomaticManagedPagefile = $false
                $cs.Put() | Out-Null
            }
        }

        $pf = Get-WmiObject Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
        if ($pf) {
            Write-Log "Existing pagefile setting: Initial=$($pf.InitialSize) MB Maximum=$($pf.MaximumSize) MB"
            if ($pf.InitialSize -ne $min) {
                Invoke-Safely "Set pagefile InitialSize to $min MB" {
                    $pf.InitialSize = $min
                    $pf.Put() | Out-Null
                    $script:RebootRequired = $true
                }
            }
            $pf = Get-WmiObject Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
            if ($pf -and $pf.MaximumSize -ne $max) {
                Invoke-Safely "Set pagefile MaximumSize to $max MB" {
                    $pf.MaximumSize = $max
                    $pf.Put() | Out-Null
                    $script:RebootRequired = $true
                }
            }
        } else {
            Invoke-Safely "Create pagefile setting (Initial=$min MB Maximum=$max MB)" {
                Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = 'C:\pagefile.sys'; InitialSize = $min; MaximumSize = $max } | Out-Null
                $script:RebootRequired = $true
            }
        }
    }
}

# --- Startup type des services ---
if ($Config.ApplyServiceStartupTweaks) {

    $disabledServices = 'AppVClient', 'NetTcpPortSharing', 'DialogBlockingService', 'UevAgentService'
    if ($Config.Telemetry.DisableDiagTrackService) { $disabledServices += 'DiagTrack' }
    if ($Config.DisableSshAgentService) { $disabledServices += 'ssh-agent' }
    foreach ($s in $disabledServices) { Set-ServiceStartupSafely -Name $s -StartupType Disabled }

    # SysMain : NVMe/SSD -> disabled, HDD avec >12GB RAM -> manual, HDD <=12GB -> disabled
    Invoke-Safely "Tune SysMain for boot drive type" {
        $ramGB = [Math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 0)
        $bootDisk = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') | Get-Disk
        $isFastDisk = $bootDisk.BusType -eq 'NVMe' -or $bootDisk.MediaType -eq 'SSD'
        if ($isFastDisk) {
            Set-ServiceStartupSafely -Name SysMain -StartupType Disabled
        } elseif ($ramGB -gt 12) {
            Set-ServiceStartupSafely -Name SysMain -StartupType Manual
        } else {
            Set-ServiceStartupSafely -Name SysMain -StartupType Disabled
        }
    }

    # Services optionnels/consommateur -> Manual. Deja exclus (comme dans le script d'origine) :
    # NlaSvc, netprofm, TokenBroker, UsoSvc, WpnService, RemoteAccess, RemoteRegistry (sensibles entreprise).
    $manualServices = @(
        'ALG', 'AppIDSvc', 'AppMgmt', 'AppReadiness', 'Appinfo', 'AssignedAccessManagerSvc', 'AxInstSV', 'BDESVC',
        'BcastDVRUserService', 'BluetoothUserService', 'BTAGService', 'bthserv', 'CaptureService', 'cbdhsvc',
        'CertPropSvc', 'cloudidsvc', 'COMSysApp', 'ClipSVC', 'ConsentUxUserSvc', 'CredentialEnrollmentManagerUserSvc',
        'CscService', 'DcpSvc', 'dcsvc', 'defragsvc', 'DevQueryBroker', 'DeviceAssociationBroker', 'DeviceAssociationService',
        'DeviceInstall', 'DevicePickerUserSvc', 'DevicesFlowUserSvc', 'diagnosticshub.standardcollector.service',
        'diagsvc', 'DisplayEnhancementService', 'DmEnrollmentSvc', 'dmwappushservice', 'dot3svc', 'DoSvc', 'embeddedmode',
        'fdPHost', 'fhsvc', 'hidserv', 'icssvc', 'EapHost', 'edgeupdate', 'edgeupdatem', 'EFS', 'EntAppSvc', 'FDResPub', 'Fax',
        'FrameServer', 'FrameServerMonitor', 'GraphicsPerfSvc', 'HvHost', 'IEEtwCollectorService', 'IKEEXT', 'IpxlatCfgSvc',
        'lfsvc', 'lltdsvc', 'lmhosts', 'LxpSvc', 'McpManagementService', 'MessagingService', 'MicrosoftEdgeElevationService',
        'MixedRealityOpenXRSvc', 'MSDTC', 'MsKeyboardFilter', 'MSiSCSI', 'msiserver', 'NPSMSvc', 'NaturalAuthentication',
        'NcaSvc', 'NcbService', 'NcdAutoSetup', 'NetSetupSvc', 'Netman', 'NgcCtnrSvc', 'NgcSvc', 'p2pimsvc', 'p2psvc',
        'P9RdrService', 'PcaSvc', 'PeerDistSvc', 'PenService', 'perceptionsimulation', 'PerfHost', 'PhoneSvc',
        'PimIndexMaintenanceSvc', 'pla', 'PlugPlay', 'PNRPAutoReg', 'PNRPsvc', 'PolicyAgent', 'PrintNotify',
        'PrintWorkflowUserSvc', 'PushToInstall', 'QWAVE', 'RasAuto', 'RasMan', 'RetailDemo', 'RmSvc', 'RpcLocator',
        'SCPolicySvc', 'ScDeviceEnum', 'SCardSvr', 'SDRSVC', 'seclogon', 'SEMgrSvc', 'SensorDataService', 'SensorService',
        'SensrSvc', 'SessionEnv', 'SharedAccess', 'SharedRealitySvc', 'shpamsvc', 'SmsRouter', 'smphost', 'SNMPTrap',
        'spectrum', 'SstpSvc', 'SSDPSRV', 'StiSvc', 'StorSvc', 'svsvc', 'swprv', 'TabletInputService', 'TapiSrv',
        'TieringEngineService', 'TimeBroker', 'TimeBrokerSvc', 'TroubleshootingSvc', 'UI0Detect', 'UdkUserSvc',
        'UmRdpService', 'UnistoreSvc', 'UserDataSvc', 'upnphost', 'VacSvc', 'vds', 'vmicguestinterface', 'vmicheartbeat',
        'vmickvpexchange', 'vmicrdv', 'vmicshutdown', 'vmictimesync', 'vmicvmsession', 'vmicvss', 'VSS', 'WalletService',
        'wbengine', 'WcsPlugInService', 'wcncsvc', 'WdNisSvc', 'WdiServiceHost', 'WdiSystemHost', 'WebClient', 'Wecsvc',
        'wercplsupport', 'WEPHOSTSVC', 'WerSvc', 'WFDSConMgrSvc', 'WiaRpc', 'WinHttpAutoProxySvc', 'WinRM', 'wisvc',
        'wlidsvc', 'wlpasvc', 'wmiApSrv', 'WMPNetworkSvc', 'WManSvc', 'WPDBusEnum', 'WpcMonSvc', 'workfolderssvc',
        'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc'
    )
    foreach ($s in $manualServices) { Set-ServiceStartupSafely -Name $s -StartupType Manual }

    $autoServices = @(
        'AudioEndpointBuilder', 'AudioSrv', 'BFE', 'BITS', 'BrokerInfrastructure', 'BthHFSrv', 'CDPUserSvc',
        'CoreMessagingRegistrar', 'CryptSvc', 'DPS', 'DcomLaunch', 'Dhcp', 'DispBrokerDesktopSvc', 'Dnscache', 'dusmsvc',
        'EventLog', 'EventSystem', 'FontCache', 'gpsvc', 'iphlpsvc', 'LSM', 'LanmanServer', 'LanmanWorkstation', 'MpsSvc',
        'nsi', 'OneSyncSvc', 'Power', 'ProfSvc', 'RpcEptMapper', 'RpcSs', 'SENS', 'SamSs', 'Schedule', 'ShellHWDetection',
        'Spooler', 'sppsvc', 'SystemEventsBroker', 'Themes', 'tiledatamodelsvc', 'TrkWks', 'tzautoupdate', 'uhssvc',
        'UserManager', 'W32Time', 'Wcmsvc', 'WinDefend', 'Winmgmt', 'WlanSvc', 'WpnUserService'
    )
    foreach ($s in $autoServices) { Set-ServiceStartupSafely -Name $s -StartupType Automatic }

    $delayedAutoServices = 'SecurityHealthService', 'WSearch', 'wscsvc', 'wuauserv', 'wudfsvc', 'XboxGipSvc'
    foreach ($s in $delayedAutoServices) { Set-ServiceStartupSafely -Name $s -StartupType DelayedAutomatic }
}

# --- Telemetrie : items cosmetiques/sans risque appliques par defaut, items sensibles
# (niveau global, service DiagTrack, WER, Delivery Optimization) laisses au repos ---
if ($Config.Telemetry.DisableFeedbackNotifications) {
    Invoke-Safely "Disable feedback notification popups" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name DoNotShowFeedbackNotifications -PropertyType DWord -Value 1 -Force | Out-Null
    }
}
if ($Config.Telemetry.DisableAdvertisingId) {
    Invoke-Safely "Disable advertising ID (machine policy)" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name DisabledByGroupPolicy -PropertyType DWord -Value 1 -Force | Out-Null
    }
}
if ($Config.Telemetry.LimitEnhancedDiagnosticData) {
    Invoke-Safely "Limit enhanced diagnostic data to Desktop/Endpoint Analytics events only" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name LimitEnhancedDiagnosticDataWindowsAnalytics -PropertyType DWord -Value 1 -Force | Out-Null
    }
}
if ($Config.Telemetry.DisableRecall) {
    Invoke-Safely "Disable Windows Recall" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name AllowRecallEnablement -PropertyType DWord -Value 0 -Force | Out-Null
    }
}
if ($Config.Telemetry.LowerTelemetryLevel) {
    Invoke-Safely "Lower telemetry level to Security (0)" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry -PropertyType DWord -Value 0 -Force | Out-Null
    }
}
if ($Config.Telemetry.DisableWindowsErrorReporting) {
    Invoke-Safely "Disable Windows Error Reporting" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name Disabled -PropertyType DWord -Value 1 -Force | Out-Null
    }
}
if ($Config.Telemetry.DisableDeliveryOptimization) {
    Invoke-Safely "Disable Delivery Optimization (P2P update distribution)" {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -PropertyType DWord -Value 0 -Force | Out-Null
    }
}
# DisableDiagTrackService est applique plus haut, dans la liste $disabledServices.

# --- Menu de boot F8 legacy (off par defaut : impacte les prompts de recuperation BitLocker) ---
if ($Config.SetLegacyBootMenu) {
    Invoke-Safely "Enable legacy F8 boot menu" {
        bcdedit /set '{default}' bootmenupolicy legacy | Out-Null
        $script:RebootRequired = $true
    }
}

# --- Gaming (seul HAGS est porte ; Ultimate Performance et lock P-state GPU volontairement exclus) ---
if ($Config.ApplyGamingTweaks) {
    Invoke-Safely "Enable Hardware-Accelerated GPU Scheduling" {
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -PropertyType DWord -Value 2 -Force | Out-Null
    }
}

# --- Preferences par profil utilisateur ---
function Set-UserPreferences {
    param([string]$BaseKey)

    if ($Config.ApplyUserPreferenceTweaks) {
        Invoke-Safely "Explorer opens to This PC ($BaseKey)" {
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name LaunchTo -PropertyType DWord -Value 1 -Force | Out-Null
        }
        Invoke-Safely "Enable End Task from taskbar ($BaseKey)" {
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name TaskbarEndTask -PropertyType DWord -Value 1 -Force | Out-Null
        }
        Invoke-Safely "Restore full right-click context menu ($BaseKey)" {
            New-Item -Path "$BaseKey\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
        }
        Invoke-Safely "Speed up menu show delay ($BaseKey)" {
            New-ItemProperty -Path "$BaseKey\Control Panel\Desktop" -Name MenuShowDelay -PropertyType String -Value '10' -Force | Out-Null
        }
    }

    if ($Config.DisableConsumerFeatures) {
        Invoke-Safely "Disable Start/Explorer ads and suggestions ($BaseKey)" {
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name BingSearchEnabled -PropertyType DWord -Value 0 -Force | Out-Null
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name ContentDeliveryAllowed -PropertyType DWord -Value 0 -Force | Out-Null
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name 'SubscribedContent-338388Enabled' -PropertyType DWord -Value 0 -Force | Out-Null
            New-ItemProperty -Path "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowCopilotButton -PropertyType DWord -Value 0 -Force | Out-Null
        }
    }
}

if ($Config.ApplyUserPreferenceTweaks -or $Config.DisableConsumerFeatures) {

    $loadedSids = Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-|^S-1-12-1-' } |
        Select-Object -ExpandProperty PSChildName

    foreach ($sid in $loadedSids) {
        Set-UserPreferences -BaseKey "Registry::HKEY_USERS\$sid"
    }

    if (Test-Path 'Registry::HKEY_USERS\TempHive') {
        Invoke-Safely "Clean up leftover TempHive from a previous run" { reg unload 'HKU\TempHive' | Out-Null }
    }

    $profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Special -and $_.SID -notin $loadedSids }

    foreach ($profile in $profiles) {
        $hivePath = Join-Path $profile.LocalPath 'NTUSER.DAT'
        if (-not (Test-Path $hivePath)) { continue }
        $loadResult = reg load 'HKU\TempHive' "$hivePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SKIPPED: could not load hive for $($profile.LocalPath) -- $loadResult"
            continue
        }
        Set-UserPreferences -BaseKey 'Registry::HKEY_USERS\TempHive'
        # Force la liberation des handles .NET avant unload, sinon "Access is denied" intermittent.
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        reg unload 'HKU\TempHive' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "WARNING: could not unload hive for $($profile.LocalPath) -- may still be mounted"
        }
    }

    $defaultHive = 'C:\Users\Default\NTUSER.DAT'
    if (Test-Path $defaultHive) {
        reg load 'HKU\DefaultHive' $defaultHive | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Set-UserPreferences -BaseKey 'Registry::HKEY_USERS\DefaultHive'
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            reg unload 'HKU\DefaultHive' | Out-Null
        } else {
            Write-Log "SKIPPED: could not load Default profile hive"
        }
    }
}

# --- Marqueur de conformite + flag de reboot (pas de reboot force) ---
New-Item -Path $MarkerPath -Force | Out-Null
Set-ItemProperty -Path $MarkerPath -Name AppliedVersion -Value $ScriptVersion -Force
Set-ItemProperty -Path $MarkerPath -Name LastRun -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
Set-ItemProperty -Path $MarkerPath -Name PendingReboot -Value ([int]$RebootRequired) -Force

Write-Log "=== Remediation finished. PendingReboot=$RebootRequired ==="
Write-Output "Remediation applied (v$ScriptVersion). Reboot required: $RebootRequired. Log: $LogFile"
exit 0
