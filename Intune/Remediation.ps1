#Requires -RunAsAdministrator
<#
Intune Proactive Remediation - portage du script batch "TBOK Windows Performance Optimizer".
Profil de defaut : parc d'entreprise (bureautique). Bascule les $Config ci-dessous pour
activer les sections desactivees par defaut (telemetrie, boot legacy, gaming).
Pas de section retrait Copilot : l'org utilise Copilot 365 (M365 Copilot dans les apps
Office), independant du Copilot consumer integre a l'OS - rien a nettoyer ici.
Intune : configurer "Run this script using the logged-on credentials" = No (execution SYSTEM),
"Enforce script signature check" selon ta politique, 64-bit PowerShell = Yes.

1.3.0 :
- Invoke-Safely passe en ErrorAction Stop et verifie $LASTEXITCODE : une erreur non
  terminante (cle absente) ou un exe natif en echec etait journalise "OK".
- Set-RegValue cree la cle manquante (AdvertisingInfo, WindowsAI, TaskbarDeveloperSettings).
- Ruches : filtre SID ancre (les "<SID>_Classes" etaient traitees comme des profils),
  profils EPM S-1-5-110-* et profils deja charges exclus.
- Services : relecture de l'etat courant, rien n'est ecrit si deja conforme ; les services
  proteges (Access denied) sont journalises SKIPPED, pas FAILED. AppIDSvc retire de la
  liste Manual (service AppLocker).
- Pagefile : ecrit directement PagingFiles (Session Manager\Memory Management) puis relu ;
  Win32_PageFileSetting.Put() renvoie "Valeur hors de la plage" sur Win11. Seuil 32 Go
  calcule sur la RAM installee (TotalPhysicalMemory exclut la memoire reservee :
  32213 Mo sur une machine de 32 Go).
- Plus aucun True/False dans la sortie standard.
#>

$ScriptVersion = '1.3.0'
$MarkerPath    = 'HKLM:\SOFTWARE\TBOK-Optimizer'
$LogDir        = "$env:ProgramData\TBOK-Optimizer"
$LogFile       = Join-Path $LogDir 'remediation.log'

$Config = @{
    CreateRestorePoint        = $true
    ApplyPerformanceTweaks    = $true    # pagefile, network throttling, SvcHostSplit, shutdown timeout, long paths
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

$script:FailureCount = 0

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line
}

# ErrorAction Stop : sans lui, une erreur non terminante (New-ItemProperty sur cle absente)
# n'atteint pas le catch et l'action est journalisee OK. Les exe natifs (powercfg, reg,
# bcdedit) ne levent rien : on controle $LASTEXITCODE. -PassThru pour recuperer le resultat
# sans polluer la sortie standard remontee a Intune.
function Invoke-Safely {
    param([string]$Description, [scriptblock]$Action, [switch]$PassThru)
    $ok = $false
    try {
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0
        & $Action | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "native command exited $LASTEXITCODE" }
        Write-Log "OK: $Description"
        $ok = $true
    } catch {
        Write-Log "FAILED: $Description -- $($_.Exception.Message)"
        $script:FailureCount++
    }
    if ($PassThru) { return $ok }
}

# New-ItemProperty ne cree pas la cle parente : AdvertisingInfo, WindowsAI,
# TaskbarDeveloperSettings n'existent pas sur un poste neuf.
function Set-RegValue {
    param([string]$Path, [string]$Name, [string]$Type, $Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
}

# Etat relu dans le registre : Get-Service en PS 5.1 ne distingue pas Automatic et
# DelayedAutomatic.
function Get-ServiceStartupType {
    param([string]$Name)
    $key = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction SilentlyContinue
    if (-not $key) { return $null }
    switch ([int]$key.Start) {
        2 { if ($key.DelayedAutostart -eq 1) { 'DelayedAutomatic' } else { 'Automatic' } }
        3 { 'Manual' }
        4 { 'Disabled' }
        default { "Start=$($key.Start)" }
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
        $current = Get-ServiceStartupType -Name $svc.Name
        if ($current -eq $StartupType) { continue }
        try {
            if ($StartupType -eq 'DelayedAutomatic') {
                $null = sc.exe config $svc.Name start= delayed-auto
                if ($LASTEXITCODE -eq 5) { throw [System.UnauthorizedAccessException]'Access denied' }
                if ($LASTEXITCODE -ne 0) { throw "sc.exe exited $LASTEXITCODE" }
            } else {
                Set-Service -Name $svc.Name -StartupType $StartupType -ErrorAction Stop
                # Set-Service -StartupType Automatic ne retire pas DelayedAutostart.
                if ($StartupType -eq 'Automatic' -and (Get-ServiceStartupType -Name $svc.Name) -eq 'DelayedAutomatic') {
                    $null = sc.exe config $svc.Name start= auto
                }
            }
            $after = Get-ServiceStartupType -Name $svc.Name
            if ($after -ne $StartupType) { throw "read back $after" }
            Write-Log "OK: service $($svc.Name) $current -> $StartupType"
        } catch {
            $msg = $_.Exception.Message
            # -and et -or ont la meme priorite en PowerShell : parentheses obligatoires.
            $inner  = $_.Exception.InnerException
            $denied = ($_.Exception -is [System.UnauthorizedAccessException]) -or
                      (($inner -is [System.ComponentModel.Win32Exception]) -and ($inner.NativeErrorCode -eq 5)) -or
                      ($msg -match 'Access denied|Acc.s refus')
            if ($denied) {
                Write-Log "SKIPPED: service $($svc.Name) $current -> $StartupType -- protected service (access denied)"
            } else {
                Write-Log "FAILED: service $($svc.Name) $current -> $StartupType -- $msg"
                $script:FailureCount++
            }
        }
    }
}

$RebootRequired = $false
Write-Log "=== Remediation started (v$ScriptVersion) ==="

# --- Point de restauration (avec repli backup registre si echec) ---
if ($Config.CreateRestorePoint) {
    Invoke-Safely "Enable System Restore on system drive" {
        Enable-ComputerRestore -Drive $env:SystemDrive
    }
    Invoke-Safely "Ensure VSS service is running" {
        if ((Get-Service -Name VSS).Status -ne 'Running') { Start-Service VSS }
    }
    Invoke-Safely "Allow immediate restore point creation" {
        Set-RegValue 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' SystemRestorePointCreationFrequency DWord 0
    }
    $rpOk = Invoke-Safely -PassThru "Create restore point 'Before Intune Optimizer Remediation'" {
        Checkpoint-Computer -Description 'Before Intune Optimizer Remediation' -RestorePointType MODIFY_SETTINGS
    }
    if (-not $rpOk) {
        Invoke-Safely "Fallback: export HKLM/HKCU registry backup" {
            reg export HKLM (Join-Path $LogDir 'HKLM-backup.reg') /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "reg export HKLM exited $LASTEXITCODE" }
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
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' NetworkThrottlingIndex DWord 0xffffffff
    }
    Invoke-Safely "Set SystemResponsiveness to 10" {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' SystemResponsiveness DWord 10
    }
    Invoke-Safely "Speed up service shutdown timeout" {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' WaitToKillServiceTimeout String '5000'
    }
    Invoke-Safely "Enable long path support" {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled DWord 1
    }

    $installedKB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
    Invoke-Safely "Set SvcHost split threshold to installed RAM" {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' SvcHostSplitThresholdInKB DWord ([uint32]$installedKB)
    }

    # PagingFiles est la valeur que Win32_PageFileSetting et Win32_ComputerSystem ecrivent
    # eux-memes ; les passer par WMI renvoie "Valeur hors de la plage" sur Win11 (Put() sur
    # une entree 0/0). Ecriture directe puis relecture. Effet au prochain redemarrage.
    #   '?:\pagefile.sys'              = gestion automatique
    #   'C:\pagefile.sys <min> <max>'  = taille fixe
    $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $ramMB  = [Math]::Round($installedKB / 1KB, 0)
    if ($ramMB -ge 32768) {
        $target = '?:\pagefile.sys'
        $label  = "automatic (RAM=$ramMB MB >= 32GB)"
    } else {
        $min    = 4096
        $max    = if ($ramMB -lt 8192) { 8192 } elseif ($ramMB -lt 16384) { 16384 } else { 24576 }
        $target = "C:\pagefile.sys $min $max"
        $label  = "Initial=$min MB Maximum=$max MB (RAM=$ramMB MB)"
    }
    $currentPf = @((Get-ItemProperty -LiteralPath $mmPath -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles)
    if ($currentPf.Count -eq 1 -and $currentPf[0] -eq $target) {
        Write-Log "OK: pagefile already $label"
    } else {
        Invoke-Safely "Set pagefile $label (was '$($currentPf -join ' | ')')" {
            Set-RegValue $mmPath PagingFiles MultiString ([string[]]@($target))
            $readBack = @((Get-ItemProperty -LiteralPath $mmPath -Name PagingFiles).PagingFiles)
            if ($readBack.Count -ne 1 -or $readBack[0] -ne $target) { throw "read back '$($readBack -join ' | ')'" }
            $script:RebootRequired = $true
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
    # AppIDSvc exclu : c'est le service d'application des regles AppLocker.
    $manualServices = @(
        'ALG', 'AppMgmt', 'AppReadiness', 'Appinfo', 'AssignedAccessManagerSvc', 'AxInstSV', 'BDESVC',
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
        'SensrSvc', 'SharedAccess', 'SharedRealitySvc', 'shpamsvc', 'SmsRouter', 'smphost', 'SNMPTrap',
        'spectrum', 'SstpSvc', 'SSDPSRV', 'StiSvc', 'StorSvc', 'svsvc', 'swprv', 'TabletInputService', 'TapiSrv',
        'TieringEngineService', 'TimeBroker', 'TimeBrokerSvc', 'TroubleshootingSvc', 'UI0Detect', 'UdkUserSvc',
        'UnistoreSvc', 'UserDataSvc', 'upnphost', 'VacSvc', 'vds', 'vmicguestinterface', 'vmicheartbeat',
        'vmickvpexchange', 'vmicshutdown', 'vmictimesync', 'vmicvmsession', 'vmicvss', 'VSS', 'WalletService',
        'wbengine', 'WcsPlugInService', 'wcncsvc', 'WdNisSvc', 'WdiServiceHost', 'WdiSystemHost', 'WebClient', 'Wecsvc',
        'wercplsupport', 'WEPHOSTSVC', 'WerSvc', 'WFDSConMgrSvc', 'WiaRpc', 'WinHttpAutoProxySvc', 'wisvc',
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
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' DoNotShowFeedbackNotifications DWord 1
    }
}
if ($Config.Telemetry.DisableAdvertisingId) {
    Invoke-Safely "Disable advertising ID (machine policy)" {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' DisabledByGroupPolicy DWord 1
    }
}
if ($Config.Telemetry.LimitEnhancedDiagnosticData) {
    Invoke-Safely "Limit enhanced diagnostic data to Desktop/Endpoint Analytics events only" {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' LimitEnhancedDiagnosticDataWindowsAnalytics DWord 1
    }
}
if ($Config.Telemetry.DisableRecall) {
    Invoke-Safely "Disable Windows Recall" {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' AllowRecallEnablement DWord 0
    }
}
if ($Config.Telemetry.LowerTelemetryLevel) {
    Invoke-Safely "Lower telemetry level to Security (0)" {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' AllowTelemetry DWord 0
    }
}
if ($Config.Telemetry.DisableWindowsErrorReporting) {
    Invoke-Safely "Disable Windows Error Reporting" {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' Disabled DWord 1
    }
}
if ($Config.Telemetry.DisableDeliveryOptimization) {
    Invoke-Safely "Disable Delivery Optimization (P2P update distribution)" {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode DWord 0
    }
}
# DisableDiagTrackService est applique plus haut, dans la liste $disabledServices.

# --- Menu de boot F8 legacy (off par defaut : impacte les prompts de recuperation BitLocker) ---
if ($Config.SetLegacyBootMenu) {
    Invoke-Safely "Enable legacy F8 boot menu" {
        bcdedit /set '{default}' bootmenupolicy legacy | Out-Null
        if ($LASTEXITCODE -eq 0) { $script:RebootRequired = $true }
    }
}

# --- Gaming (seul HAGS est porte ; Ultimate Performance et lock P-state GPU volontairement exclus) ---
if ($Config.ApplyGamingTweaks) {
    Invoke-Safely "Enable Hardware-Accelerated GPU Scheduling" {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode DWord 2
    }
}

# --- Preferences par profil utilisateur ---
function Set-UserPreferences {
    param([string]$BaseKey)

    if ($Config.ApplyUserPreferenceTweaks) {
        Invoke-Safely "Explorer opens to This PC ($BaseKey)" {
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" LaunchTo DWord 1
        }
        Invoke-Safely "Enable End Task from taskbar ($BaseKey)" {
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" TaskbarEndTask DWord 1
        }
        Invoke-Safely "Restore full right-click context menu ($BaseKey)" {
            $clsid = "$BaseKey\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            if (-not (Test-Path -LiteralPath $clsid)) { New-Item -Path $clsid -Force | Out-Null }
            # Valeur par defaut vide (et non absente) : c'est elle qui desactive le menu Win11.
            Set-ItemProperty -LiteralPath $clsid -Name '(default)' -Value ''
        }
        Invoke-Safely "Speed up menu show delay ($BaseKey)" {
            Set-RegValue "$BaseKey\Control Panel\Desktop" MenuShowDelay String '10'
        }
    }

    if ($Config.DisableConsumerFeatures) {
        Invoke-Safely "Disable Start/Explorer ads and suggestions ($BaseKey)" {
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled DWord 0
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" ContentDeliveryAllowed DWord 0
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-338388Enabled' DWord 0
            Set-RegValue "$BaseKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ShowCopilotButton DWord 0
        }
    }
}

if ($Config.ApplyUserPreferenceTweaks -or $Config.DisableConsumerFeatures) {

    # Ancre de fin obligatoire : HKU contient aussi "<SID>_Classes", qui n'est pas une ruche
    # de profil. Seuls les comptes locaux/AD (S-1-5-21) et Entra (S-1-12-1) sont traites ;
    # les comptes virtuels EPM (S-1-5-110-*) et de service sont hors perimetre.
    $userSidPattern = '^S-1-(5-21|12-1)(-\d+)+$'

    $loadedSids = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $userSidPattern } |
        Select-Object -ExpandProperty PSChildName)

    foreach ($sid in $loadedSids) {
        Set-UserPreferences -BaseKey "Registry::HKEY_USERS\$sid"
    }

    if (Test-Path -LiteralPath 'Registry::HKEY_USERS\TempHive') {
        Invoke-Safely "Clean up leftover TempHive from a previous run" { reg unload 'HKU\TempHive' }
    }

    # Loaded : ruche ouverte par un autre processus, reg load echouerait.
    $profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Special -and -not $_.Loaded -and $_.SID -match $userSidPattern -and $_.SID -notin $loadedSids }

    foreach ($profile in $profiles) {
        $hivePath = Join-Path $profile.LocalPath 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $hivePath)) { continue }
        $loadResult = reg load 'HKU\TempHive' "$hivePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SKIPPED: could not load hive for $($profile.LocalPath) -- $loadResult"
            continue
        }
        Set-UserPreferences -BaseKey 'Registry::HKEY_USERS\TempHive'
        # Force la liberation des handles .NET avant unload, sinon "Access is denied" intermittent.
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        reg unload 'HKU\TempHive' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "WARNING: could not unload hive for $($profile.LocalPath) -- may still be mounted"
        }
    }

    $defaultHive = 'C:\Users\Default\NTUSER.DAT'
    if (Test-Path -LiteralPath $defaultHive) {
        reg load 'HKU\DefaultHive' $defaultHive 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Set-UserPreferences -BaseKey 'Registry::HKEY_USERS\DefaultHive'
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            reg unload 'HKU\DefaultHive' 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "WARNING: could not unload Default profile hive -- may still be mounted"
            }
        } else {
            Write-Log "SKIPPED: could not load Default profile hive"
        }
    }
}

# --- Marqueur de conformite + flag de reboot (pas de reboot force) ---
New-Item -Path $MarkerPath -Force | Out-Null
Set-ItemProperty -LiteralPath $MarkerPath -Name AppliedVersion -Value $ScriptVersion -Force
Set-ItemProperty -LiteralPath $MarkerPath -Name LastRun -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
Set-ItemProperty -LiteralPath $MarkerPath -Name PendingReboot -Value ([int]$RebootRequired) -Force
Set-ItemProperty -LiteralPath $MarkerPath -Name FailureCount -Value $script:FailureCount -Force

Write-Log "=== Remediation finished. Failures=$($script:FailureCount) PendingReboot=$RebootRequired ==="
Write-Output "Remediation applied (v$ScriptVersion). Failures: $($script:FailureCount). Reboot required: $RebootRequired. Log: $LogFile"
exit 0
