# BIOS checklists

Always first: save the current settings as a profile ("stock") so the user can roll back in one step.
If the board is not listed: look up the vendor's BIOS manual for that chipset generation (ASUS: dlcdnets.asus.com/pub/ASUS/mb/13MANUAL/...) and give exact paths.

## ASUS Intel 600/700 series (PRIME / TUF GAMING / ProArt) - verified on TUF GAMING B660M-E D4, BIOS 4003
Enter: Del at power-on, F7 = Advanced Mode.
| Goal | Path | Value |
|---|---|---|
| Save profile | Tool > ASUS User Profile > Save to Profile | slot 1 "stock" |
| XMP | Ai Tweaker > Ai Overclock Tuner | XMP II (kit's full profile, most compatible) or XMP I (ASUS-tuned subtimings) |
| Gear | Ai Tweaker > Memory Controller : DRAM Frequency Ratio | Auto (1:1 preferred; 1:2 if unstable) |
| Power limits | Ai Tweaker > Performance Preferences | Intel Default Settings (stability) |
| PCIe speed | Advanced > System Agent (SA) Configuration > PCI Express Configuration > PCIEX16 link speed | Auto |
| ReBAR | Advanced > PCI Subsystem Settings > Above 4G Decoding + Re-Size BAR | Enabled |
| VT-x | Advanced > CPU Configuration > Intel (VMX) Virtualization Technology | Enabled |
| VT-d | Advanced > System Agent (SA) Configuration > VT-d | Enabled |
| TPM | Advanced > PCH-FW Configuration > TPM Device Selection | Firmware TPM |
| CSM | Boot > CSM (Compatibility Support Module) > Launch CSM | Disabled (needed for Secure Boot/ReBAR) |
| Secure Boot | Boot > Secure Boot > OS Type | Windows UEFI Mode; Key Management > Install default Secure Boot keys if in Setup mode |
| Fast Boot | Boot > Boot Configuration > Fast Boot | optional |
| Armoury Crate auto-install | Tool > ASUS Armoury Crate > Download & Install ARMOURY CRATE app | Disabled |
| Leave Auto | CPU C-states, SpeedStep, Speed Shift, ASPM | Auto |
Secure Boot prerequisites: UEFI boot (bcdedit shows winload.efi), GPT system disk, BitLocker off or recovery key saved.
Board slot facts (TUF B660M-E D4): PCIEX16_1 = CPU PCIe 4.0 x16; PCIEX16_2 = chipset PCIe 3.0 (x4 mode); PCIEX1 = chipset 3.0 x1.

## Q-LED (ASUS) meanings
Red CPU, Yellow DRAM, White VGA, Green BOOT. A LED that stays lit marks the failing stage.

## XMP failed to boot
Board usually retries and falls back. Otherwise Clear CMOS (CLRTC jumper or remove coin battery 1 min) and load the "stock" profile. Then try 1:2 gear or one step lower speed.
