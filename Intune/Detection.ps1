<#
Intune Proactive Remediation - Detection.
Exit 0 = conforme (rien a faire). Exit 1 = non conforme (declenche Remediation.ps1).
Verifie un marqueur de version + une derive concrete (taille du pagefile) plutot que de
re-tester individuellement les ~150 services : plus rapide, et evite de reproduire la
fragilite du script d'origine sur des controles repetes a chaque cycle de detection.
#>

$ScriptVersion = '1.0.0'
$MarkerPath    = 'HKLM:\SOFTWARE\TBOK-Optimizer'

try {
    $marker = Get-ItemProperty -Path $MarkerPath -ErrorAction Stop
    $versionMatches = $marker.AppliedVersion -eq $ScriptVersion

    $pfExpectedOk = $true
    $ramMB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 0)
    if ($ramMB -lt 32768) {
        $min = 4096
        $max = if ($ramMB -lt 8192) { 8192 } elseif ($ramMB -lt 16384) { 16384 } else { 24576 }
        $pf = Get-WmiObject Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
        $pfExpectedOk = [bool]($pf -and $pf.InitialSize -eq $min -and $pf.MaximumSize -eq $max)
    }

    if ($versionMatches -and $pfExpectedOk) {
        Write-Output "Compliant: optimizer v$ScriptVersion applied, pagefile sizing correct."
        exit 0
    } else {
        Write-Output "Non-compliant: versionMatches=$versionMatches pagefileOk=$pfExpectedOk"
        exit 1
    }
} catch {
    Write-Output "Non-compliant: marker not found -- $($_.Exception.Message)"
    exit 1
}
