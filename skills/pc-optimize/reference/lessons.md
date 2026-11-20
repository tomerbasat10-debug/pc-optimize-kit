# Lessons learned (real session, i5-12600K / ASUS TUF B660M-E D4 / RTX 3060 Ti, Windows 11 26H2)

## Measurement
- **Read PCIe values carefully.** nvidia-smi columns: gen.current, gen.max, width.current, width.max. A width of 4 of 16 was misread as x16 once - the GPU was in the chipset slot the whole time. Invoke-Scan now checks DEVPKEY_PciDevice_CurrentLinkWidth vs MaxLinkWidth and the parent root port.
- Which root port? CPU PEG port = bus 0 device 1 (Intel); chipset ports are "PCI Express Root Port #N" at device 0x1C/0x1D/0x1A. GPU behind a chipset port = secondary slot (often PCIe 3.0 x4 shared over DMI).
- **LatencyMon cannot be automated** (Delphi UI: no UIA buttons, F5 ignored) and its "Save report" wrote 0-byte files. Use `Measure-Dpc.ps1` (same ETW source). If the user runs LatencyMon manually: Start, wait 10 full minutes, Stop, then copy the report text (paste in chat).
- LatencyMon/ETW numbers: the red "trouble with real-time audio" verdict fires on any DPC > ~1 ms. For gaming, look at spikes >= 2 ms and the driver responsible.
- WinSAT `d3d` is deprecated (prints 42 F/s for everything) - don't use it.
- Cinebench R23 single-core takes ~10 min; the window stays open with the score - closing it early loses the result. If killed early the CSV/stdout has no score.
- Idle CPU/RAM baselines include the Claude app itself - keep conditions identical between before/after.
- `MSAcpi_ThermalZoneTemperature` is not CPU temperature. Use LibreHardwareMonitor (PawnIO driver; old WinRing0 driver is flagged by Defender - LHM >= 0.9.5 uses PawnIO).
- In LHM storage sensors, exclude "Warning/Critical Temperature" (those are limits, e.g. 87 C), use "Composite Temperature".

## Installing / downloading
- winget can fail with "Installer hash does not match" when a vendor reuses a URL (LatencyMon). Then download from the official site and verify Authenticode. Check the signer is really the vendor (Resplendence is a trademark of SoftRev Labs S.r.l.s.).
- winget manifests can point to removed versions (HWiNFO 404). hwinfo.com blocks scripted downloads with Cloudflare - do not bypass; ask the user or use LHM.
- ASUS support API (no auth): `https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=global&model=<model>&osid=52` returns direct dlcdnets.asus.com links and SHA-256 for some files.
- GitHub release assets expose `digest: sha256:...` via the API - verify against it for unsigned open-source tools.
- Driver packages may bundle an unsigned `pnputil.exe` - always use `%windir%\System32\pnputil.exe`.
- **NVIDIA silent install: never `setup.exe -s -clean` on a trimmed package.** It removed the old driver, then failed 0x80070005 -> GPU Code 28 (Basic Display). Recovery: `pnputil /add-driver Display.Driver\<matching>.inf /install` (find the INF containing `PCI\VEN_10DE&DEV_xxxx&SUBSYS_yyyyyyyy`). setup.exe afterwards fails 0xE4000008 (GetPackageDataFromOEMInf) - harmless. NVIDIA Control Panel = Microsoft Store app 9NF8H0H7WMLT (usually auto-installs after reboot).
- NVIDIA package extracts with Windows `tar -xf <exe>`.
- Run Defender check / Driver Easy check: driver updaters are a finding, not a tool.

## Windows / PowerShell gotchas
- PowerShell 5.1 reads BOM-less .ps1 as ANSI: keep scripts ASCII-only or save with BOM.
- `H` is an alias of Get-History - don't name functions H/R/etc.
- `$Args` is an automatic variable - never use it as a parameter name.
- C# in Add-Type: a class deriving from Form must not define `Events` (hides Component.Events -> warning-as-error).
- `Start-Process -Verb RunAs` cancel/timeout = non-terminating error: use `-ErrorAction Stop` + try/catch.
- `Checkpoint-Computer` blocked by the 24 h limit only WARNS - verify the restore point count. Restore point creation can hang while Windows Update/TrustedInstaller is servicing.
- Display modes: use the C# DEVMODE helper (PCOptDisplay); EnumDisplaySettings with a PowerShell [ref] struct returned 0x0 @ 0 Hz.
- HKLM reg export of GraphicsDrivers\Configuration needs admin (harmless if skipped).

## Interpreting events
- **Kernel-Power 41 with BugcheckCode 0 and SleepInProgress 6 right after a BIOS change + Kernel-Boot 29 (0xC00000D4)** = Fast Startup image invalidated by the hardware change. Not a crash.
- Kernel-Power 41 with PowerButtonTimestamp != 0 = user held the power button. Ask before assuming instability.
- Ntfs 55 on the USB installer stick (E:) = ignore, unplug the stick.
- WHEA 17 (corrected) once per boot on the root port of the Realtek 2.5GbE = link-training noise, benign.
- Intel Platform License Manager Service 7009 timeout after the MEI package = harmless.

## Hardware diagnosis (ASUS Q-LED)
- White = VGA, green = BOOT, yellow = DRAM, red = CPU. White stays lit = GPU not initialised in that slot.
- Damaged top PCIe slot pattern: broken retention latch; GPU not detected at Auto; detected once at Gen1 then hang; next boot not detected. Test path: reseat + power cables + 2 min wait -> Clear CMOS -> link speed Gen1 -> monitor on iGPU and check from Windows whether the CPU PEG root port/GPU enumerates -> another PCIe card. If it fails: keep GPU in the secondary slot and disclose when selling.
