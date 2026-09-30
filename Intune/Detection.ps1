<#
Intune Proactive Remediation - Detection.
Exit 0 = conforme (rien a faire). Exit 1 = non conforme (declenche Remediation.ps1).
Verifie un marqueur de version + une derive concrete (taille du pagefile) plutot que de
re-tester individuellement les ~150 services : plus rapide, et evite de reproduire la
fragilite du script d'origine sur des controles repetes a chaque cycle de detection.
Le pagefile est relu dans PagingFiles, la valeur que la remediation ecrit : meme source,
meme calcul de RAM (installee, pas TotalPhysicalMemory).
#>

$ScriptVersion = '1.3.0'
$MarkerPath    = 'HKLM:\SOFTWARE\TBOK-Optimizer'
$MmPath        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

try {
    $marker = Get-ItemProperty -LiteralPath $MarkerPath -ErrorAction Stop
    $versionMatches = $marker.AppliedVersion -eq $ScriptVersion

    $ramMB = [Math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1MB, 0)
    if ($ramMB -ge 32768) {
        $target = '?:\pagefile.sys'
    } else {
        $max = if ($ramMB -lt 8192) { 8192 } elseif ($ramMB -lt 16384) { 16384 } else { 24576 }
        $target = "C:\pagefile.sys 4096 $max"
    }
    $pf = @((Get-ItemProperty -LiteralPath $MmPath -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles)
    $pfExpectedOk = ($pf.Count -eq 1 -and $pf[0] -eq $target)

    if ($versionMatches -and $pfExpectedOk) {
        Write-Output "Compliant: optimizer v$ScriptVersion applied, pagefile '$target'. Failures last run: $($marker.FailureCount)"
        exit 0
    } else {
        Write-Output "Non-compliant: versionMatches=$versionMatches pagefileOk=$pfExpectedOk (found '$($pf -join ' | ')', expected '$target')"
        exit 1
    }
} catch {
    Write-Output "Non-compliant: marker not found -- $($_.Exception.Message)"
    exit 1
}
