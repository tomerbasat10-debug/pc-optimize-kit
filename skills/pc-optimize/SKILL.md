---
name: pc-optimize
description: Set up and tune a Windows 11 desktop for low input lag gaming plus productivity, safely and reversibly. Use when the user asks to optimize, tune, set up, check or speed up a PC, reduce input lag/latency, check drivers/BIOS/XMP, install their regular apps on a new PC, or verify stability. Scans hardware, finds real problems, proposes changes in approval batches with backup + undo, measures before/after.
---

# PC Optimize

A proven, step-by-step workflow for a freshly installed (or existing) Windows 11 desktop. Goal: best measurable performance and lowest input latency while staying 100% stable. Scripts do the work; you analyse, explain, ask approval, verify.

Talk to the user in their language (Hebrew users: answer in Hebrew). Be concise; tables over prose.

## Ground rules (non-negotiable)
1. **Scan and measure freely (read-only). Change nothing without explicit approval.** Present changes in batches; for each item give: what / why (measurable) / risk / how to undo.
2. Every change goes through a script that backs up first and writes the journal (`<root>\journal.jsonl`). `Revert-All.ps1` must be able to undo it. BIOS changes are done by the user and documented.
3. No debloat packs, no "tweak" bundles, no driver updaters (Driver Easy, Driver Booster, ...). Official vendor sources only (winget, vendor sites, GitHub releases with verified digest/signature).
4. Never disable Defender, Windows Update, VBS/Memory Integrity, Secure Boot, UAC without explaining the risk and getting explicit approval.
5. Call out placebo/harmful tweaks instead of applying them (see `reference/tweaks.md`).
6. Never claim success without verifying (re-run the check). Report failures honestly, including your own mistakes.
7. Do not install software from archives of paid software from unofficial sources (cracks). Flag it, suggest the official installer.

## Setup
- Scripts: `scripts\` next to this file. Work root: `$env:PCOPT_ROOT` (default `C:\PCOptimize`): logs, backups, baseline, scan, tools, journal.
- Claude usually runs NON-elevated. For admin scripts use `Invoke-Elevated` from `scripts\lib\Common.ps1` or `Start-Process powershell -Verb RunAs -Wait -ErrorAction Stop` inside try/catch. A UAC prompt appears: TELL the user to click Yes. A cancelled/timed-out UAC (2 min) is a non-terminating error: always check it ran (log/output file exists).
- Long runs (Cinebench, DPC trace 10 min): run in background, tell the user not to touch the PC, wait for the notification.
- Keep `<root>\PROGRESS.md` updated (done / pending / next step). After any reboot read it first.

## Workflow
### 1. Scan (read-only) - `Invoke-Scan.ps1` (elevated for SMART/TPM/boot time; works non-elevated too)
Produces `scan\scan-*.md/json` with findings ranked HIGH/MED/LOW. Typical HIGH findings on a fresh install:
- Display below max refresh (e.g. 60 Hz on a 240 Hz monitor) - biggest latency win.
- RAM at JEDEC speed while kit is rated higher (XMP/EXPO off).
- Devices with Code 28 (missing chipset INF / Serial IO / MEI).
- **GPU PCIe link width below x16** (GPU in chipset slot, not seated, or damaged slot). Link SPEED dropping at idle is normal; WIDTH is not.
- Driver updaters / old inbox LAN driver.
Then: `Get-VendorDrivers.ps1` (board drivers + BIOS latest; ASUS via official API) and look up latest GPU driver on the vendor site.

### 2. Baseline (read-only)
- Ask approval to install tools: `Install-Tools.ps1` (elevated) - LHM+PawnIO (temps), PresentMon, NPI (NVIDIA), Cinebench R23 + OCCT.
- `Measure-Baseline.ps1 -Tag before [-Cinebench]` (elevated). `Measure-Dpc.ps1 -Tag before -Seconds 600` (elevated, idle PC). `Test-Stability.ps1 -Tag before` (temps idle + 3 min load).
- Mouse: `powershell -STA -File Measure-MousePolling.ps1` while the user moves the mouse in circles.

### 3. BIOS check (from Windows) + manual checklist
Report: BIOS version vs latest, XMP/EXPO (rated vs actual), ReBAR (NVIDIA BAR1 > 256 MiB = on), Secure Boot, TPM, virtualization, PCIe link. Give the user an exact menu checklist for THEIR board (see `reference/bios.md`; look up the vendor BIOS manual if not listed). Tell them to save a "stock" BIOS profile first. After the visit: verify RAM speed, Secure Boot, link width; explain Kernel-Power 41 after BIOS changes (see lessons).

### 4. Input-lag analysis
Rank causes highest to lowest impact (refresh rate, XMP, VRR/V-Sync/Reflex config, GPU driver DPC spikes, missing chipset drivers, mouse polling, background load, power plan, PCIe). Use DPC results, not folklore.

### 5. Changes in approval batches (each script journals + supports Revert)
| Batch | Script | Notes |
|---|---|---|
| Display | `Set-Display.ps1 -Mode Apply` | max Hz at current resolution |
| Input | `Set-Mouse.ps1 -Mode Apply` | acceleration off |
| Drivers | `Install-DriverPackage.ps1 -Path <pkg> -Kind Inf/Nvidia/Setup` | one package at a time, LAN last (network blips). Verify vendor SHA-256 / Authenticode first. NVIDIA: `-Kind Nvidia` (INF install), never `setup.exe -clean` |
| GPU latency | `Set-GpuLatency.ps1 -Mode Apply -GSync Keep/On/Off` | ask the user about G-SYNC/FreeSync preference and game types first |
| Apps | `Install-Apps.ps1 -Folder <folder> -Mode Plan`, then `-Mode Install` | user's own installer folder; winget preferred |
Reboot when drivers ask (3010). After reboot: re-scan, re-check 240 Hz, problem devices, NVIDIA Control Panel present.

### 6. Stability + report
- `Test-Stability.ps1 -Tag after`, `Measure-Dpc.ps1 -Tag after`, `Measure-Baseline.ps1 -Tag after`.
- If XMP/EXPO was enabled: RAM test in OCCT (GUI: Stability Test > MEMORY, 30-60 min). If the user declines, document "XMP not stress-tested" + how to roll back.
- Check Event Log since changes (WHEA, bugchecks). `New-Report.ps1` -> `FINAL-REPORT.md`. Recommend a full system image once clean.

### Antivirus question
Default answer: Microsoft Defender is sufficient (top-tier AV-Test/AV-Comparatives protection, no ads, no extra product). Only research alternatives if the user asks; use the latest AV-Test / AV-Comparatives reports.

## Must-read before acting
- `reference/lessons.md` - pitfalls that cost hours last time (read it!).
- `reference/tweaks.md` - safe / depends / not recommended.
- `reference/bios.md` - menu paths for known boards + Q-LED meanings.
