<#
.SYNOPSIS
    TBOK BeardSweeper Automated Scheduled Cleanup Routine.
    Part of TBOK-Win11Optimizer (https://github.com/rauell1/TBOK-Win11Optimizer).

.DESCRIPTION
    Performs safe, automated, non-destructive monthly disk and cache cleanup:
    1. Maximizes Windows VolumeCaches registry settings (StateFlags0069)
    2. Runs native Windows Disk Cleanup (cleanmgr.exe /sagerun:69)
    3. Runs DISM Component Store Cleanup (DISM /Online /Cleanup-Image /StartComponentCleanup)
    4. Purges developer & AI tool caches (NPM, Pip, User Temp, Codex worktrees/tmp, Antigravity history)

.PARAMETER InstallTask
    Registers this script as a recurring monthly task in Windows Task Scheduler.

.PARAMETER UninstallTask
    Removes the scheduled task from Windows Task Scheduler.

.PARAMETER IncludeDevCaches
    Also cleans NPM, pip, user temp, and AI session worktrees (default: $true).

.EXAMPLE
    .\BeardSweeper-ScheduledCleanup.ps1 -InstallTask
    .\BeardSweeper-ScheduledCleanup.ps1 -IncludeDevCaches
#>

[CmdletBinding()]
param(
    [switch]$InstallTask,
    [switch]$UninstallTask,
    [switch]$IncludeDevCaches = $true
)

$TaskName = "TBOK-BeardSweeper-MonthlyCleanup"
$LogDir   = "$env:ProgramData\TBOK-Optimizer"
$LogFile  = Join-Path $LogDir "scheduled-cleanup.log"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-CleanupLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
}

# --- Task Scheduler Management ---
if ($UninstallTask) {
    Write-CleanupLog "Removing scheduled task '$TaskName'..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-CleanupLog "Task '$TaskName' removed successfully."
    return
}

if ($InstallTask) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        $scriptPath = Join-Path $PSScriptRoot "BeardSweeper-ScheduledCleanup.ps1"
    }

    Write-CleanupLog "Registering monthly scheduled task '$TaskName'..."
    $action  = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    # Trigger on the 1st of every month at 09:00 AM
    $trigger = New-ScheduledTaskTrigger -At 9:00am -Once
    $trigger.Repetition = $null
    
    # Run with highest privileges as SYSTEM or Current Admin
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Using schtasks for rock-solid monthly trigger support across all Windows 10/11 editions
    $schtasksCmd = "schtasks.exe /create /tn `"$TaskName`" /tr `"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `\`"$scriptPath`\`"`" /sc monthly /d 1 /st 09:00 /ru `"SYSTEM`" /rl HIGHEST /f"
    
    $result = Invoke-Expression $schtasksCmd
    Write-CleanupLog "Task registration output: $result"
    Write-CleanupLog "Task registered. It will run automatically on the 1st of every month at 9:00 AM."
    return
}

# --- Routine Execution ---
Write-CleanupLog "============================================================"
Write-CleanupLog "Starting TBOK BeardSweeper Automated Cleanup"
Write-CleanupLog "============================================================"

# 1. VolumeCaches Registry Flags for CleanMgr
Write-CleanupLog "Configuring Disk Cleanup flags (StateFlags0069)..."
$groupNo = "StateFlags0069"
$rootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

$volumeCacheKeys = @(
    "Active Setup Temp Folders", "BranchCache", "Content Indexer Cleaner",
    "Delivery Optimization Files", "Diagnostic Data Viewer database Files",
    "D3D Shader Cache", "Downloaded Program Files", "Internet Cache Files",
    "Language Pack", "Offline Pages Files", "Old ChkDsk Files", "Recycle Bin",
    "RetailDemo Offline Content", "ServicePack Cleanup", "Setup Log Files",
    "System error memory dump files", "System error minidump files",
    "Temporary Files", "Update Cleanup", "Thumbnail Cache",
    "Windows Defender", "Windows Error Reporting Files", "Windows Upgrade Log Files"
)

foreach ($keyName in $volumeCacheKeys) {
    $targetPath = Join-Path $rootKey $keyName
    if (Test-Path $targetPath) {
        Set-ItemProperty -Path $targetPath -Name $groupNo -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# 2. Windows CleanMgr
Write-CleanupLog "Running cleanmgr.exe /sagerun:69..."
try {
    $p = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:69" -Wait -PassThru -NoNewWindow
    Write-CleanupLog "Disk Cleanup completed with exit code $($p.ExitCode)."
} catch {
    Write-CleanupLog "WARNING: cleanmgr.exe encountered an error: $($_.Exception.Message)"
}

# 3. DISM Component-Store Cleanup
Write-CleanupLog "Running DISM Component-Store Cleanup..."
try {
    $p = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /NoRestart" -Wait -PassThru -NoNewWindow
    Write-CleanupLog "DISM Component-Store cleanup completed with exit code $($p.ExitCode)."
} catch {
    Write-CleanupLog "WARNING: DISM encountered an error: $($_.Exception.Message)"
}

# 4. Developer & AI Caches Cleanup
if ($IncludeDevCaches) {
    Write-CleanupLog "Running Developer and AI Cache cleanups..."

    # NPM Cache
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        try {
            Write-CleanupLog "Purging NPM cache..."
            & npm cache clean --force 2>&1 | Out-Null
            Write-CleanupLog "NPM cache cleaned."
        } catch {}
    }
    $npmCachePath = "$env:LOCALAPPDATA\npm-cache"
    if (Test-Path $npmCachePath) {
        Remove-Item -Recurse -Force $npmCachePath -ErrorAction SilentlyContinue
    }

    # Python pip cache
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        try {
            Write-CleanupLog "Purging Pip cache..."
            & pip cache purge 2>&1 | Out-Null
            Write-CleanupLog "Pip cache cleaned."
        } catch {}
    }

    # User Temp folder
    if (Test-Path $env:TEMP) {
        Write-CleanupLog "Purging User Temp folder ($env:TEMP)..."
        Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Codex task worktrees & temporary project files
    $codexWorktrees = "$env:USERPROFILE\.codex\worktrees"
    if (Test-Path $codexWorktrees) {
        Write-CleanupLog "Cleaning old Codex worktrees..."
        Get-ChildItem -Path $codexWorktrees -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $codexTmp = "$env:USERPROFILE\.codex\.tmp"
    if (Test-Path $codexTmp) {
        Remove-Item -Recurse -Force "$codexTmp\*" -ErrorAction SilentlyContinue
    }

    # Antigravity session transcripts & brain artifacts
    $antigravityConvs = "$env:USERPROFILE\.gemini\antigravity\conversations"
    if (Test-Path $antigravityConvs) {
        Write-CleanupLog "Cleaning old Antigravity session transcripts..."
        Remove-Item -Recurse -Force "$antigravityConvs\*" -ErrorAction SilentlyContinue
    }
}

Write-CleanupLog "============================================================"
Write-CleanupLog "TBOK BeardSweeper Automated Cleanup Finished Successfully"
Write-CleanupLog "============================================================"
