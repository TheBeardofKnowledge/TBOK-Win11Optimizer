# Proposal: version- and edition-aware settings engine

This is a **proposal for discussion**, not a pull request to merge. It is one
possible way to make TBOK apply only the settings that actually work on the
machine in front of it, and to make every change reversible.

## Why

Many settings in `TBOKwinOptimizer.bat` only take effect on certain Windows
builds or editions, and a few land in the wrong place. Examples confirmed
against Microsoft documentation:

- `AllowTelemetry=0` is honored only on Enterprise, Education and Server. On
  Pro it is treated as `1` (Required), so the log reports a change that Windows
  does not enforce.
- `RemoveMicrosoftCopilotApp` is Enterprise/Education, 24H2+ only.
- `TurnOffWindowsCopilot` is a per-user policy that is deprecated and only
  governs the pre-24H2 Copilot pane; the machine-scope write has no effect.
- News/widgets need `EnableFeeds` on Windows 10 but `AllowNewsAndInterests`
  on Windows 11.
- Taskbar items such as the Teams Chat icon and the 23H2 Copilot button exist
  only on specific builds.

Blind application is not harmful here (Windows ignores what it does not
understand), but the log becomes misleading and the script carries dead writes.

## What is here

- **`TBOK-Settings.csv`**: 121 rows, one per setting, each tagged with:
  minimum/maximum build, editions, hardware/management requirements, an action
  (`Apply` / `Review` / `Drop`), the evidence level (`Doc` where a Microsoft
  page was found, `Community`, or `Undocumented`), a note, and a source link.
- **`TBOK-Apply.ps1`**: reads the CSV, detects the machine (build, edition
  family, battery/Modern Standby, domain/MDM management, Edge, Office), and
  applies only the rows that fit. Features:
  - `-Plan` prints what would change and the exact reason each skipped row was
    skipped (a per-machine report, changes nothing).
  - every change is journaled with its previous value; `-Undo <journal>`
    restores it.
  - `-Group Optimize|Gaming|All` matches the existing batch switches.
  - writes to `Current` and `Default` control sets only, never `LastKnownGood`.
  - finds user profiles from the registry profile list and unloads offline
    hives with retries.

## Status / caveats

- Tested off-box only: CSV parsing, the build/edition/requirement gate logic
  against five simulated machines, and the helper functions, under PowerShell
  7. **Not** tested against a live registry. The registry writes, hive
  load/unload and `-Undo` need a run on a Windows test VM.
- A few build ranges (taskbar items, the windowed-games key) come from
  community testing, marked `Community` in the CSV. Rows marked `Doc` carry a
  Microsoft Learn link.
- This does not change `TBOKwinOptimizer.bat`. If the approach is wanted, the
  machine-wide registry block and the per-user loop could call this script
  instead; that wiring is intentionally left out of this proposal.
