# TBOK Windows Performance Optimizer

<p align="center">
<img src="https://github.com/TheBeardofKnowledge/TBOK-Win11Optimizer/blob/main/TBOK171menu.png" />
</p>
A business ready comprehensive Hardware-aware Windows 10 and Windows 11 configuration and cleanup script for personal PC's and managed workstations.

The scripts change Windows settings, policies, services, and per-user preferences in order to improve system responsiveness, improve gaming/workstation performance, and increase user privacy.

2 versions are available: 
1. standalone batch file: TBOKwinOptimizer.bat  ( use this on your personal pc, keep on usb, or when Intune is not available to you)
2. Intune deployment files for Enterprise business use (folder).

If you haven't noticed, Windows 11 is not fully optimized, in fact, it's unnecessarily bloated and needs tuning. 
It's not your computer, it's Microsoft's bad decisions on failure to streamline their OS for modern hardware. But there's hope... the Dev's left us a way to change it.
Yes, this also improves LTSC versions, including IoT... the parts that don't apply just gracefully fail or get ignored, but ~80% is still aplicable.

You see, most debloat tools* only modify the existing user account that you ran it with... but Windows made a lot of settings that are considered "bloat" a per-user setting.  While I love tools like the CTT WinUtil, Ralphire's Win11Debloat, and Belim's FlyByOOBE or CrapFixer, when you work with hundreds of computers like I do, you're not doing to manually configure these options on each pc, and for each user: that's extremely inefficient and time consuming... and you're definitely NOT going to IRM a github script in an Enterprise environment, right?! RIGHT!? 

This is a problem for Custom PC builders & IT people because they tune and configure a pc after install, but when a new person signs in with their own account on that PC; all the bad settings and bloat come back. 

So let's fix that and make it soo easy and safe that it removes any hurdles.**

The script applies a selected set of system and per-user registry changes, with hardware-dependent choices for supported settings.

The script applies per-user settings to eligible existing profiles and the Default profile for future accounts. Service and special profiles are excluded where detected.

It removes selected built-in packages and disables selected scheduled tasks and consumer features. 

The scripts require usable rollback protection before protected optimization changes. By default, they requires a system restore point; if creation fails, it exports registry hives for manual recovery and cancels the run. Registry exports are not a complete system restore.

So what does it do?

1. Disables "Fast Startup" aka hibernation mode for desktops (keep enabled for laptops)
2. Enables the legacy F8 boot menu only when BitLocker is detected as off; it is skipped if BitLocker is on or its status is unknown.
3. Properly configures virtual memory settings to avoid lag from expansion
4. Services:
   1. Disables a few unnecessary services from startup
   2. Configures the sysmain and MMAgent services based on your hardware (ram/storage)
   3. Ensures services that don't have to autorun on startup are set to demand startup
   4. Ensures required windows services are set to automatic startup
   5. Configures less essential services to delayed startup

5. System Wide Registry Improvements
   1. Disables Windows Network Throttling
   2. Fixes IRP stack size for better network flow and modern networks
   3. Improve system responsiveness
   4. Sets the service shutdown wait to 15 seconds
   5. Enables long file system paths (why is this not defaulted ON Microsoft?)
   6. Disables "Companion software" recommendations for hardware
   7. Disables Webview mode from Windows Search, returning classic search
   8. Disables known Telemetry Data Collection
   9. Disables the Windows OOBE Privacy Settings Experience prompt for new users.
   10. Disables WPBT execution without overwriting the firmware resource value
   11. Fixes the Network Data Usage Graph not working
   12. Disables various system telemetry
   13. Disables various intrusive MS Edge settings, including background startup
   14. Disables MS Recall from being auto enabled
   15. Enables verbose logon and logoff messages so you can know what your system is doing

6. Bloat Removal
   1. Removes MS Co-Pilot standard version (not m365 co-pilot) systemwide for all users and disables auto reinstall/enable
   2. Removes Bing Search systemwide
   3. Removes Taskbar Widgets that load a full web browser in RAM even if you don't use it
   4. Removes the WebExperienceHost package that MS uses to push content
   5. Disables Various Wasteful scheduled tasks that autorun even without consent

7. User Level Registry Improvements (applied to all users, including default profile) (sysprep)
   This is what most optimization and debloat utilities get wrong - they only apply it to the current user, when MS clearly made bloat & data collection per user.
   1. Preserves existing Explorer folder views by default; `/RESETEXPLORERVIEWS` opts into resetting them
   2. Sets "This PC" as the default explorer view
   3. Disable allow apps to run in the background (even when closed)
   4. Force Auto Enable Game Mode which helps reduce background apps
   5. Enable right-click "End Task" feature from taskbar
   6. Restore Full classic Context menu right-click menu
   7. Disable web search in start menu search
   8. Allow pinning more apps in the start menu
   9. Speed up "show menu" delay for classic apps
   10. Disable some gaudy desktop visual effects and animations that affect reaction time
   11. Disable Ad spaces (The OS is NOT a billboard Microsoft)
   12. Disable Explorer Search box suggestions
   13. Disable File Explorer sync provider ads
   14. Disable reoccurring "finish setup" ad suggestions to "get the most out of windows"
   15. Disable lock screen tips and ads
   16. Disable Ad Personalization (tracking)
   17. Disable Welcome Experience Ads
   18. Disable Settings ads
   19. Disable auto install of suggested apps (related to #3 above)
   20. Disable General tips and ads (why are these together Microsoft?)
   21. Disable home screen ads
   22. Disable Timeline Suggestions ads
   23. Disable Windows Content Delivery
   24. Disable automatic enabling of OEM and Preinstalled apps (LG monitor McAfee ad incident)
   25. Disable Diagnostic Feedback frequency and "Tailored Experiences"
   26. Disable the Windows Feeds as policy or standard
   27. Disable the Start Menu ads
   28. Disable the Tailored Experiences with Telemetry feature
   29. Disable the Task View button in the taskbar - wasted space and same as alt+tab
   30. Disable the People button in the taskbar (auto launches teams)
   31. Enable the taskbar end tasks feature (related to #5 above)
   32. Hide the "meet now" button in the taskbar (related to #13 above)
   33. Set the taskbar search box for icon only for less wasted space (works the same)
   34. Disable Cross-device resume (optional, but skip this if you use "your phone")
   35. Leaves StickyKeys accessibility settings unchanged
   36. Leaves `ssh-agent` startup unchanged for SSH and developer workflows
   37. Leaves `AutoEndTasks` disabled unless `/ALLOWFORCECLOSE` is specified

8. Debloat and removal of wasteful scheduled tasks
   1. Disable MS Copilot (standard, not M365 co-pilot)
   2. Disable Microsoft Office logging
   3. Disable Microsoft Office Client Telemetry and verbose logging
   4. Disable Microsoft Office "Customer Experience Program"
   5. Disable Microsoft Office Feedback

9. Gaming Improvements (improved 1% lows, reduce lag, improve frame timing)
   1. Reset High Precision Event Timer preconfigured so Windows will redetect on next boot
   2. Enable Hardware Accelerated GPU scheduling (will only work if your hardware supports HAGS)
   3. Enable Optimizations for Windowed Games
   4. Increase system responsiveness for Games
   5. Set improved MMCS values for Windowed Games and Audio Apps
   6. Desktop - Disable Power Throttling and Lazy Mode
   7. Desktop - Enable Ultimate Performance Power Plan
   8. Set processor ramp up to aggressive at guaranteed for desktops and (race to idle) and efficient aggressive for laptops.

10. WinGet automatic software updater
11. Ultimate Disk Cleanup with my own script - BeardSweeper - More comprehensive cleanup than most or all utilities and scripts. Pending full implementation.

MORE TO COME, but after testing... I am not going to add anything that is a placebo or unverified improvement.

*(excluding Ralphire's sysprep mode)
**Effects vary by Windows build, hardware, and workload. Review the code and test on representative devices before broad deployment; no optimizer can guarantee that every feature or application remains unaffected.  The batch script uses hardware-aware decisions for selected settings. Some operations are Windows-edition or hardware dependent and may be skipped or fail; review the log after each run.  Windows has many configurable behaviors. Some are tradeoffs or preferences, so the script keeps several potentially disruptive choices opt-in through /switches. Settings are selected to target common configuration preferences, but they can still affect application behavior, accessibility, security tooling, or performance on a particular device in your environment. Review the options and logs before deployment. Performance changes depend on the machine and workload. Measure before and after rather than assuming a particular improvement.  These changes can affect user workflows and may need to be reversed or re-enabled after deployment.

IF THIS HELPED YOU OUT -CONSIDER BUYING ME A COFFEE- THATS WHAT POWERED THIS
<https://buymeacoffee.com/thebeardofl>
