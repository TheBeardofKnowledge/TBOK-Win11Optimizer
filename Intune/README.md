# TBOK Optimizer for Intune (Proactive Remediations)

A headless, business-fleet-friendly port of the ideas in `TBOKwinOptimizer.bat`, meant to
run unattended as a Microsoft Intune Proactive Remediation instead of interactively on a
single PC.

It does **not** replace the `.bat` script - that one is still the right tool for a single
personal/gaming PC you run by hand. This is for pushing a safe subset of the same tweaks
across a managed fleet.

## Why a separate script instead of just running the .bat via Intune

The `.bat` script assumes an interactive session: it self-elevates via UAC, shows a
`CHOICE` menu, and prompts to reboot at the end. None of that works under Intune, which
runs scripts headlessly (as SYSTEM by default) with no user to answer prompts - a
prompt like the final Y/N reboot question would just hang forever. `Remediation.ps1` is a
rewrite of the safe/relevant subset of the tweaks with no interactive steps, no forced
reboot (see below), and idempotent PowerShell instead of one-shot batch calls.

## Files

- **Detection.ps1** - exit `0` if the target state is already applied, `1` otherwise.
  Checks the applied version, a zero `FailureCount`, and one concrete drift check
  (pagefile sizing). It does not re-verify every service or registry setting, so a later
  external change to those settings is not detected by this script.
- **Remediation.ps1** - applies the tweaks. Runs only when Detection.ps1 exits `1`.

## Setup in Intune

Devices and monitoring > Scripts and remediations > Create:

- Detection script file: `Detection.ps1`
- Remediation script file: `Remediation.ps1`
- Run this script using the logged-on credentials: **No** (runs as SYSTEM)
- Enforce script signature check: per your org's policy
- Run script in 64-bit PowerShell host: **Yes**

## What's different from the .bat script, on purpose

- **No forced reboot.** The original prompts "Restart now? [Y/N]" at the end, which is
  fine on your own PC but not on a fleet. `Remediation.ps1` instead writes
  `HKLM:\SOFTWARE\TBOK-Optimizer\PendingReboot` (`1`/`0`) so you can react to it via your
  own reporting/compliance policy instead of rebooting unattended machines mid-workday.
- **Rollback gate.** With the default `$Config.CreateRestorePoint = $true`, a system restore
  point must be created before optimizer changes run. If it cannot be created, the script
  attempts HKLM/HKCU registry exports and cancels without applying tweaks even if those
  exports succeed. They are limited manual recovery aids, not a full system rollback.
- **Pagefile bug fix.** `Set-CimInstance` against `Win32_PageFileSetting` throws
  `Value out of range` on a number of builds (a known CIM provider quirk with that class -
  it round-trips read-only properties on write). It's a non-terminating error, so the
  original script's `try/catch` never catches it and logs a false "Configured pagefile"
  success even when nothing changed. `Get-WmiObject`/`.Put()` turned out to fail the same
  way on Windows 11 (on the default `0 0` system-managed entry), so since 1.3.0
  `Remediation.ps1` writes the `PagingFiles` value under
  `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` directly -
  the same value WMI itself writes - and reads it back before reporting success. Takes
  effect on next reboot. Fixed-size pagefiles use the Windows system drive, and detection
  uses the same path. The 32 GB "automatic" threshold uses installed RAM
  (`Win32_PhysicalMemory`), because `TotalPhysicalMemory` excludes hardware-reserved
  memory and a 32 GB machine reports about 32213 MB.
- **Conservative defaults for a managed fleet**, toggled via the `$Config` block at the
  top of `Remediation.ps1`:
  - Telemetry is split into individual toggles instead of one on/off switch. The
    cosmetic ones (feedback popups, advertising ID, Recall, limiting enhanced diagnostic
    data) are on by default. The ones that can degrade Defender for Endpoint / Update
    Compliance / Windows Update for Business reporting (lowering the telemetry level,
    disabling the DiagTrack service, disabling WER, disabling Delivery Optimization) are
    off by default - flip them only after checking with whoever owns security/infra
    reporting for the fleet.
  - No Windows Copilot removal - out of scope for orgs using Microsoft 365 Copilot
    (a separate product from the OS-level consumer Copilot), and not something every org
    will want touched centrally.
  - Legacy F8 boot menu, gaming tweaks (except HAGS) and consumer-feature/ad removal are
    off by default - see the comments next to each flag in `Remediation.ps1`.

## Changelog

### 1.3.1

- Require a restore point before applying changes; registry exports alone are not treated
  as complete rollback protection, and both export exit codes are checked. Restore the
  temporary restore-point frequency setting.
- Keep failed runs non-compliant so Intune retries them; profile hive load/unload failures
  are included in `FailureCount`.
- Use the Windows system drive for the fixed pagefile and Default profile hive, and skip
  special profiles in both loaded and offline profile passes.

### 1.3.0

Fixes found by running 1.2.0 elevated on a real Windows 11 machine:

- **Failures logged as `OK`.** `New-ItemProperty` on a missing key raises a
  non-terminating error, which never reached the `catch` in `Invoke-Safely`. It now runs
  actions with `ErrorAction Stop` and checks `$LASTEXITCODE` for native tools
  (`powercfg`, `reg`, `bcdedit`).
- **Missing registry keys.** `AdvertisingInfo`, `WindowsAI` and
  `TaskbarDeveloperSettings` don't exist on a fresh install, and `New-ItemProperty` does
  not create parent keys. New `Set-RegValue` helper creates the key first.
- **`<SID>_Classes` hives treated as user profiles.** The SID filter `^S-1-12-1-` also
  matched `S-1-12-1-..._Classes`. It is now anchored (`^S-1-(5-21|12-1)(-\d+)+$`), and
  virtual-account profiles (`S-1-5-110-*`, e.g. EPM elevation accounts) and already-loaded
  profiles are skipped.
- **Pagefile never applied** - see above.
- **Services.** The current startup type is read from the registry first and nothing is
  written if it already matches. Almost all "Access denied" failures were on protected
  services that were already at the target value. Genuine access-denied on a protected
  service is now logged as `SKIPPED`, not `FAILED`. `AppIDSvc` is no longer forced to
  Manual: it enforces AppLocker.
- No more `True`/`False` noise in the output collected by Intune. A `FailureCount` is
  written to `HKLM:\SOFTWARE\TBOK-Optimizer` and shown in the last output line.
- Full right-click context menu: the empty default value is now written explicitly.
- `Detection.ps1` now uses the same RAM calculation and reads the pagefile from
  `PagingFiles`. Before, detection could never validate the pagefile, so the remediation
  would have rerun on every cycle.
