#Requires -Version 5.1
<#
TBOK-Apply.ps1
Applies registry rows from TBOK-Settings.csv only where they fit this machine
(build, edition, hardware, management state). Every change is journaled so it
can be reversed with -Undo.

  -Plan            Show what would apply and why each skipped row was skipped. Changes nothing.
  -IncludeReview   Also apply rows whose Action is Review.
  -AllowManaged    Write Policies keys even on domain-joined or MDM-enrolled devices.
  -Undo <journal>  Restore every value recorded in a previous journal.
  -Group           Optimize (default), Gaming, or All; matches the batch switches.
  -ContextOverride Hashtable used for testing gate logic off-box.
Exit codes: 0 success, 1 one or more failures, 2 refused (unsupported platform or bad input).
#>
[CmdletBinding()]
param(
    [string]$Manifest = (Join-Path $PSScriptRoot 'TBOK-Settings.csv'),
    [string]$Journal,
    [switch]$Plan,
    [switch]$IncludeReview,
    [switch]$AllowManaged,
    [string]$Undo,
    [ValidateSet('Optimize', 'Gaming', 'All')][string]$Group = 'Optimize',
    [hashtable]$ContextOverride
)

$ErrorActionPreference = 'Stop'
$script:Failures = 0
$RegExe = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\reg.exe' } else { 'reg.exe' }

function Write-Log([string]$Message) { Write-Output ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) }

function ConvertTo-BuildVersion([string]$Text, [switch]$Upper) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $parts = $Text.Trim().Split('.')
    $build = [int]$parts[0]
    if ($parts.Count -gt 1) { $ubr = [int]$parts[1] }
    elseif ($Upper) { $ubr = [int]::MaxValue }
    else { $ubr = 0 }
    return New-Object Version 10, 0, $build, $ubr
}

function Get-EditionFamily([string]$EditionId, [string]$InstallationType) {
    if ($InstallationType -eq 'Server') { return @('Server') }
    switch -Regex ($EditionId) {
        '^(EnterpriseS|EnterpriseSN|IoTEnterpriseS|IoTEnterpriseSK)$' { return @('Ent', 'IoT', 'LTSC') }
        '^IoTEnterprise' { return @('IoT') }
        '^Enterprise' { return @('Ent') }
        '^Education' { return @('Edu') }
        '^Professional' { return @('Pro') }
        '^Core' { return @('Home') }
        default { return @('Unknown') }
    }
}

function Get-PowerCapabilities {
    # SYSTEM_POWER_CAPABILITIES: AoAc (Modern Standby) is byte 20, SystemBatteriesPresent is byte 30.
    try {
        if (-not ('Tbok.Power' -as [type])) {
            Add-Type -Namespace 'Tbok' -Name 'Power' -MemberDefinition '[DllImport("powrprof.dll")] public static extern byte GetPwrCapabilities(System.IntPtr caps);'
        }
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(256)
        try {
            if ([Tbok.Power]::GetPwrCapabilities($buffer) -eq 0) { return $null }
            return [pscustomobject]@{
                ModernStandby = ([Runtime.InteropServices.Marshal]::ReadByte($buffer, 20) -ne 0)
                HasBattery    = ([Runtime.InteropServices.Marshal]::ReadByte($buffer, 30) -ne 0)
            }
        } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
    } catch { return $null }
}

function Get-TbokContext {
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $cv = $hklm.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
    $build = [int]$cv.GetValue('CurrentBuildNumber')
    $ubr = [int]$cv.GetValue('UBR', 0)
    $edition = [string]$cv.GetValue('EditionID')
    $installType = [string]$cv.GetValue('InstallationType')
    $display = [string]$cv.GetValue('DisplayVersion')
    $cv.Close()

    $power = Get-PowerCapabilities
    $partOfDomain = $false
    try { $partOfDomain = [bool](Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain } catch { }
    $mdm = $false
    $enroll = $hklm.OpenSubKey('SOFTWARE\Microsoft\Enrollments')
    if ($enroll) {
        foreach ($sub in $enroll.GetSubKeyNames()) {
            $k = $enroll.OpenSubKey($sub)
            if ($k -and [string]$k.GetValue('ProviderID') -eq 'MS DM Server') { $mdm = $true }
            if ($k) { $k.Close() }
        }
        $enroll.Close()
    }
    $edge = $false
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($pf -and (Test-Path -LiteralPath (Join-Path $pf 'Microsoft\Edge\Application\msedge.exe'))) { $edge = $true }
    }
    $office = $null -ne $hklm.OpenSubKey('SOFTWARE\Microsoft\Office\ClickToRun\Configuration')
    $hklm.Close()

    $ctx = @{
        Build = $build; UBR = $ubr; DisplayVersion = $display
        Version = New-Object Version 10, 0, $build, $ubr
        EditionId = $edition; InstallationType = $installType
        Families = Get-EditionFamily $edition $installType
        IsWindows11 = ($build -ge 22000)
        ModernStandby = $(if ($power) { $power.ModernStandby } else { $null })
        HasBattery = $(if ($power) { $power.HasBattery } else { $null })
        Managed = ($partOfDomain -or $mdm)
        Edge = $edge; Office = $office
    }
    return $ctx
}

function Test-RowApplies($Row, $Ctx, [bool]$IsLoadedHive) {
    # Returns $null when the row applies, otherwise the reason it was skipped.
    if ($Row.Action -eq 'Drop') { return 'action Drop' }
    if ($Row.Action -eq 'Review' -and -not $IncludeReview) { return 'action Review (use -IncludeReview)' }
    if ($Row.Type -eq 'COMPUTED') { return 'value is computed by the batch script' }
    $min = ConvertTo-BuildVersion $Row.MinBuild
    $max = ConvertTo-BuildVersion $Row.MaxBuild -Upper
    if ($min -and $Ctx.Version -lt $min) { return ('build {0} below minimum {1}' -f $Ctx.Version, $Row.MinBuild) }
    if ($max -and $Ctx.Version -gt $max) { return ('build {0} above maximum {1}' -f $Ctx.Version, $Row.MaxBuild) }
    if ($Row.Editions -and $Row.Editions -ne 'All') {
        $allowed = $Row.Editions.Split(';')
        if (-not ($Ctx.Families | Where-Object { $allowed -contains $_ })) {
            return ('edition {0} not in {1}' -f $Ctx.EditionId, $Row.Editions)
        }
    }
    if ($Row.Requires) {
        foreach ($token in $Row.Requires.Split(';')) {
            $ok = switch ($token) {
                'Desktop'          { $Ctx.HasBattery -eq $false }
                'Laptop'           { $Ctx.HasBattery -eq $true }
                'NotModernStandby' { $Ctx.ModernStandby -eq $false }
                'Unmanaged'        { -not $Ctx.Managed }
                'Edge'             { [bool]$Ctx.Edge }
                'Office'           { [bool]$Ctx.Office }
                'LoadedHive'       { $IsLoadedHive }
                default            { $false }
            }
            if (-not $ok) { return ('requirement {0} not met' -f $token) }
        }
    }
    if ($Ctx.Managed -and -not $AllowManaged -and $Row.Path -match '(^|\\)Policies\\') {
        return 'managed device; Policies keys belong to GPO or MDM (use -AllowManaged)'
    }
    return $null
}

function ConvertTo-RegData([string]$Type, [string]$Value) {
    switch ($Type) {
        'DWORD'    { $n = [uint32][uint64]$Value; return @([BitConverter]::ToInt32([BitConverter]::GetBytes($n), 0), [Microsoft.Win32.RegistryValueKind]::DWord) }
        'QWORD'    { $n = [uint64]$Value; return @([BitConverter]::ToInt64([BitConverter]::GetBytes($n), 0), [Microsoft.Win32.RegistryValueKind]::QWord) }
        'SZ'       { return @($Value, [Microsoft.Win32.RegistryValueKind]::String) }
        'EXPANDSZ' { return @($Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
        'BINARY'   { $bytes = [byte[]]@(for ($i = 0; $i -lt $Value.Length; $i += 2) { [Convert]::ToByte($Value.Substring($i, 2), 16) }); return @($bytes, [Microsoft.Win32.RegistryValueKind]::Binary) }
        default    { throw "Unsupported type $Type" }
    }
}

function Merge-SzFlags([string]$Existing, [string]$Flags) {
    # Merge key=value pairs into a semicolon-delimited flag string, keeping unrelated flags.
    $map = [ordered]@{}
    foreach ($pair in ([string]$Existing).Split(';')) {
        if ($pair -match '^\s*([^=]+)=(.*)$') { $map[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    foreach ($pair in $Flags.Split(';')) {
        if ($pair -match '^\s*([^=]+)=(.*)$') { $map[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    return ((@($map.Keys | ForEach-Object { '{0}={1}' -f $_, $map[$_] }) -join ';') + ';')
}

function Set-RowValue($BaseKey, [string]$HiveId, $Row, [System.Collections.ArrayList]$JournalList) {
    $name = if ($Row.Name -eq '(Default)') { '' } else { $Row.Name }
    $existing = $BaseKey.OpenSubKey($Row.Path, $false)
    $priorExists = $false; $priorKind = $null; $priorData = $null
    if ($existing) {
        if ($existing.GetValueNames() -contains $name) {
            $priorExists = $true
            $priorKind = $existing.GetValueKind($name).ToString()
            $priorData = $existing.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        }
        $existing.Close()
    }
    if ($Row.Type -eq 'SZFLAGS') {
        $data = Merge-SzFlags ([string]$priorData) $Row.Value
        $kind = [Microsoft.Win32.RegistryValueKind]::String
    } else {
        $converted = ConvertTo-RegData $Row.Type $Row.Value
        $data = $converted[0]; $kind = $converted[1]
    }
    $same = $priorExists -and $priorKind -eq $kind.ToString() -and
            ((($data -is [byte[]]) -and ([Convert]::ToBase64String($data) -eq [Convert]::ToBase64String([byte[]]$priorData))) -or
             (-not ($data -is [byte[]]) -and "$priorData" -eq "$data"))
    $label = '{0} {1}\{2}\{3}' -f $Row.Id, $HiveId, $Row.Path, $Row.Name
    if ($same) { Write-Log "MATCH   $label"; return }
    if ($Plan) { Write-Log "WOULD   $label = $($Row.Value) [$($Row.Type)]"; return }
    try {
        $key = $BaseKey.CreateSubKey($Row.Path)
        try { $key.SetValue($name, $data, $kind) } finally { $key.Close() }
        $priorSerialized = if ($priorData -is [byte[]]) { 'b64:' + [Convert]::ToBase64String($priorData) } elseif ($priorData -is [string[]]) { 'multi:' + ($priorData -join "`n") } else { $priorData }
        [void]$JournalList.Add([pscustomobject]@{
            Id = $Row.Id; Hive = $HiveId; Path = $Row.Path; Name = $name
            PriorExists = $priorExists; PriorKind = $priorKind; PriorData = $priorSerialized
        })
        Write-Log ("SET     $label = $($Row.Value) [$($Row.Type)]" + $(if ($priorExists) { " (was $priorData)" } else { ' (was absent)' }))
    } catch {
        $script:Failures++
        Write-Log "ERROR   $label : $($_.Exception.Message)"
    }
}

function Invoke-ForEachHive([scriptblock]$Action) {
    # Calls $Action with (baseKey, hiveId, isLoaded) for HKLM, then each user hive.
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    & $Action $hklm 'HKLM' $false
    $users = [Microsoft.Win32.RegistryKey]::OpenBaseKey('Users', 'Registry64')
    $loaded = @($users.GetSubKeyNames() | Where-Object { $_ -match '^S-1-(5-21|12-1)-[\d-]+$' })
    foreach ($sid in $loaded) {
        $root = $users.OpenSubKey($sid, $true)
        try { & $Action $root $sid $true } finally { $root.Close() }
    }
    $profileList = $hklm.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')
    $offline = New-Object System.Collections.ArrayList
    foreach ($sid in $profileList.GetSubKeyNames()) {
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$' -or $loaded -contains $sid) { continue }
        $p = $profileList.OpenSubKey($sid)
        $path = [Environment]::ExpandEnvironmentVariables([string]$p.GetValue('ProfileImagePath'))
        $p.Close()
        if ($path -and (Test-Path -LiteralPath (Join-Path $path 'NTUSER.DAT'))) { [void]$offline.Add(@($sid, (Join-Path $path 'NTUSER.DAT'))) }
    }
    $defaultDir = [Environment]::ExpandEnvironmentVariables([string]$profileList.GetValue('Default'))
    $profileList.Close()
    if ($defaultDir -and (Test-Path -LiteralPath (Join-Path $defaultDir 'NTUSER.DAT'))) { [void]$offline.Add(@('DEFAULT', (Join-Path $defaultDir 'NTUSER.DAT'))) }
    $hklm.Close()

    foreach ($entry in $offline) {
        $hiveId = $entry[0]; $file = $entry[1]
        $mount = 'TBOK_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        & $RegExe load "HKU\$mount" $file 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "SKIP    $hiveId hive could not be loaded (in use or locked)"; continue }
        try {
            $root = $users.OpenSubKey($mount, $true)
            try { & $Action $root $hiveId $false } finally { if ($root) { $root.Close() } }
        } finally {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
            $unloaded = $false
            for ($try = 1; $try -le 5 -and -not $unloaded; $try++) {
                & $RegExe unload "HKU\$mount" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $unloaded = $true } else { Start-Sleep -Milliseconds (400 * $try) }
            }
            if (-not $unloaded) { $script:Failures++; Write-Log "ERROR   $hiveId hive still mounted at HKU\$mount; unload it before that user signs in" }
        }
    }
    $users.Close()
}

# ---------------- Undo ----------------
if ($Undo) {
    # PowerShell 5.1 emits a JSON array as one object; ForEach-Object flattens it.
    $entries = @((Get-Content -LiteralPath $Undo -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
    [array]::Reverse($entries)
    Invoke-ForEachHive {
        param($base, $hiveId, $isLoaded)
        foreach ($e in ($entries | Where-Object { $_.Hive -eq $hiveId })) {
            $label = '{0} {1}\{2}\{3}' -f $e.Id, $hiveId, $e.Path, $e.Name
            try {
                $key = $base.OpenSubKey($e.Path, $true)
                if (-not $key) { Write-Log "SKIP    $label key no longer exists"; continue }
                try {
                    if (-not $e.PriorExists) { $key.DeleteValue($e.Name, $false); Write-Log "REMOVED $label" }
                    else {
                        $kind = [Microsoft.Win32.RegistryValueKind]$e.PriorKind
                        $data = [string]$e.PriorData
                        if ($data.StartsWith('b64:')) { $data = [Convert]::FromBase64String($data.Substring(4)) }
                        elseif ($data.StartsWith('multi:')) { $data = [string[]]$data.Substring(6).Split("`n") }
                        elseif ($kind -eq 'DWord') { $data = [int]$e.PriorData }
                        elseif ($kind -eq 'QWord') { $data = [long]$e.PriorData }
                        $key.SetValue($e.Name, $data, $kind); Write-Log "RESTORE $label"
                    }
                } finally { $key.Close() }
            } catch { $script:Failures++; Write-Log "ERROR   $label : $($_.Exception.Message)" }
        }
    }
    exit $(if ($script:Failures) { 1 } else { 0 })
}

# ---------------- Apply / Plan ----------------
if (-not (Test-Path -LiteralPath $Manifest)) { Write-Log "ERROR   manifest not found: $Manifest"; exit 2 }
$rows = @(Import-Csv -LiteralPath $Manifest)
if ($Group -ne 'All') { $rows = @($rows | Where-Object { $(if ($_.Group) { $_.Group } else { 'Optimize' }) -eq $Group }) }
if ($rows.Count -eq 0) { Write-Log "ERROR   no manifest rows for group $Group"; exit 2 }
$required = 'Id','Scope','Path','Name','Type','Value','MinBuild','MaxBuild','Editions','Requires','Action'
$missing = @($required | Where-Object { $rows[0].PSObject.Properties.Name -notcontains $_ })
if ($missing.Count) { Write-Log ("ERROR   manifest missing columns: " + ($missing -join ', ')); exit 2 }

$ctx = if ($ContextOverride) { $ContextOverride } else { Get-TbokContext }
Write-Log ('Detected: build {0} ({1}) edition {2} families {3} install {4}' -f $ctx.Version, $ctx.DisplayVersion, $ctx.EditionId, ($ctx.Families -join '/'), $ctx.InstallationType)
Write-Log ('Detected: ModernStandby={0} Battery={1} Managed={2} Edge={3} Office={4}' -f $ctx.ModernStandby, $ctx.HasBattery, $ctx.Managed, $ctx.Edge, $ctx.Office)

if ($ctx.Families -contains 'Server') { Write-Log 'REFUSED Windows Server is not a supported target for TBOK'; exit 2 }
if ($ctx.Build -lt 19045) { Write-Log 'REFUSED builds older than Windows 10 22H2 are not supported'; exit 2 }

$journalList = New-Object System.Collections.ArrayList
if ($ContextOverride) {
    # Off-box test mode: evaluate gates only.
    foreach ($row in $rows) {
        $isLoaded = ($row.Scope -eq 'User')
        $reason = Test-RowApplies $row $ctx $isLoaded
        if ($reason) { Write-Log "SKIP    $($row.Id) $($row.Name): $reason" } else { Write-Log "APPLIES $($row.Id) $($row.Name)" }
    }
    exit 0
}

Invoke-ForEachHive {
    param($base, $hiveId, $isLoaded)
    $scope = if ($hiveId -eq 'HKLM') { 'Machine' } else { 'User' }
    foreach ($row in ($rows | Where-Object { $_.Scope -eq $scope })) {
        $reason = Test-RowApplies $row $ctx $isLoaded
        if ($reason) {
            if ($hiveId -eq 'HKLM' -or $hiveId -eq 'DEFAULT') { Write-Log "SKIP    $($row.Id) $hiveId $($row.Name): $reason" }
            continue
        }
        Set-RowValue $base $hiveId $row $journalList
    }
}

if (-not $Plan -and $journalList.Count -gt 0) {
    if (-not $Journal) { $Journal = Join-Path $PSScriptRoot ('TBOK-Journal-{0}-{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    $journalList | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Journal -Encoding UTF8
    Write-Log "Journal written: $Journal ($($journalList.Count) changes). Reverse with -Undo `"$Journal`""
}
Write-Log ("Finished with {0} failure(s)" -f $script:Failures)
exit $(if ($script:Failures) { 1 } else { 0 })
