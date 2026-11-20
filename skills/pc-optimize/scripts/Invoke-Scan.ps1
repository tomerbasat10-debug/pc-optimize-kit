# Invoke-Scan.ps1 - READ-ONLY full system scan. Works as normal user; run elevated for SMART, Secure Boot, TPM, boot time.
# Output: <root>\scan\scan-<stamp>.json and scan-<stamp>.md (findings ranked HIGH > MED > LOW > INFO).
param([string]$OutDir)
. "$PSScriptRoot\lib\Common.ps1"
$root = Initialize-Workspace
if (-not $OutDir) { $OutDir = Join-Path $root 'scan' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$admin = Test-Admin
$S = [ordered]@{ Time = (Get-Date -Format 's'); Admin = $admin }
$F = New-Object System.Collections.Generic.List[object]
function Add-Finding($Sev, $Area, $Text, $Fix) { $F.Add([pscustomobject]@{ Severity = $Sev; Area = $Area; Finding = $Text; Suggested = $Fix }) }
function TryGet([scriptblock]$b) { try { & $b } catch { $null } }

# ---------------- OS ----------------
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$S.OS = [ordered]@{ Caption = $os.Caption; Version = $cv.DisplayVersion; Build = "$($os.BuildNumber).$($cv.UBR)"; Installed = $os.InstallDate; LastBoot = $os.LastBootUpTime }

# ---------------- CPU / board / BIOS ----------------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$bb  = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
$cs = Get-CimInstance Win32_ComputerSystem
$S.CPU = [ordered]@{ Name = $cpu.Name.Trim(); Cores = $cpu.NumberOfCores; Threads = $cpu.NumberOfLogicalProcessors; BaseMHz = $cpu.MaxClockSpeed; HypervisorPresent = $cs.HypervisorPresent }
$S.Board = [ordered]@{ Manufacturer = $bb.Manufacturer; Product = $bb.Product; BIOS = $bios.SMBIOSBIOSVersion; BIOSDate = $bios.ReleaseDate; BIOSVendor = $bios.Manufacturer }
if (-not $cs.HypervisorPresent -and -not $cpu.VirtualizationFirmwareEnabled) { Add-Finding 'LOW' 'BIOS' 'CPU virtualization (VT-x/SVM) appears disabled in BIOS' 'Enable Intel VMX / AMD SVM if you use WSL, VMs, Sandbox or VBS' }

# ---------------- RAM (XMP/EXPO heuristic) ----------------
$dimms = @(Get-CimInstance Win32_PhysicalMemory)
$S.RAM = @($dimms | ForEach-Object { [ordered]@{ Slot = $_.DeviceLocator; GB = [math]::Round($_.Capacity/1GB); Maker = $_.Manufacturer; Part = ($_.PartNumber).Trim(); Speed = $_.Speed; Configured = $_.ConfiguredClockSpeed; Type = $_.SMBIOSMemoryType } })
$S.RAMTotalGB = [math]::Round(($dimms | Measure-Object Capacity -Sum).Sum/1GB)
$cfg = ($dimms | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
$rated = 0; foreach ($d in $dimms) { if ($d.PartNumber -match '(\d{4})C\d{2}' -or $d.PartNumber -match '(?<!\d)(2[4-9]\d{2}|3\d{3}|[4-8]\d{3})(?!\d)') { $v = [int]$Matches[1]; if ($v -gt $rated -and $v -le 9000) { $rated = $v } } }
$S.RAMRatedFromPart = $rated
$jedec = @(2133, 2400, 2666, 2933, 3200, 4800, 5200, 5600)
if ($rated -gt 0 -and $cfg -lt $rated - 100) { Add-Finding 'HIGH' 'RAM' "RAM runs at $cfg MT/s but the part number suggests $rated MT/s - XMP/EXPO is probably OFF" 'BIOS: enable XMP (Intel) / EXPO or DOCP (AMD); then run a memory stability test' }
elseif ($rated -eq 0 -and $jedec -contains $cfg) { Add-Finding 'MED' 'RAM' "RAM runs at a JEDEC default speed ($cfg MT/s); could not read the kit rating from the part number" 'Check the kit label / vendor site; enable XMP/EXPO if the kit is rated higher' }
if ($dimms.Count -eq 2) { $chan = $dimms | ForEach-Object { $_.DeviceLocator -replace 'DIMM.*','' } | Sort-Object -Unique; if ($chan.Count -lt 2) { Add-Finding 'HIGH' 'RAM' 'Both DIMMs appear to be on the same channel (single-channel)' 'Move DIMMs to the board-recommended slots (usually A2 + B2)' } }

# ---------------- GPU / display / PCIe link ----------------
$gpus = @(Get-CimInstance Win32_VideoController)
$S.GPU = @(foreach ($g in $gpus) {
    $o = [ordered]@{ Name = $g.Name; Driver = $g.DriverVersion; DriverDate = $g.DriverDate; Status = $g.Status; PNP = $g.PNPDeviceID }
    $dev = Get-PnpDevice -InstanceId $g.PNPDeviceID -ErrorAction SilentlyContinue
    if ($dev -and $g.PNPDeviceID -like 'PCI\*') {
        foreach ($k in 'DEVPKEY_PciDevice_CurrentLinkWidth','DEVPKEY_PciDevice_MaxLinkWidth','DEVPKEY_PciDevice_CurrentLinkSpeed','DEVPKEY_PciDevice_MaxLinkSpeed') { $o[$k -replace 'DEVPKEY_PciDevice_',''] = (Get-PnpDeviceProperty -InstanceId $g.PNPDeviceID -KeyName $k -ErrorAction SilentlyContinue).Data }
        $par = (Get-PnpDeviceProperty -InstanceId $g.PNPDeviceID -KeyName DEVPKEY_Device_Parent -ErrorAction SilentlyContinue).Data
        if ($par) { $o.ParentPort = (Get-PnpDevice -InstanceId $par -ErrorAction SilentlyContinue).FriendlyName; $o.ParentId = ($par -replace '&SUBSYS.*','') }
        $o.Location = (Get-PnpDeviceProperty -InstanceId $g.PNPDeviceID -KeyName DEVPKEY_Device_LocationInfo -ErrorAction SilentlyContinue).Data
    }
    $o })
foreach ($g in $S.GPU) {
    if ($g.Status -ne 'OK') { Add-Finding 'HIGH' 'GPU' "$($g.Name) status is $($g.Status)" 'Check Device Manager / reinstall driver' }
    if ($g.CurrentLinkWidth -and $g.MaxLinkWidth -and $g.MaxLinkWidth -ge 8 -and $g.CurrentLinkWidth -lt $g.MaxLinkWidth) {
        Add-Finding 'HIGH' 'GPU' "$($g.Name) PCIe link is x$($g.CurrentLinkWidth) of x$($g.MaxLinkWidth) (parent: $($g.ParentPort))" 'GPU is probably in a chipset/secondary slot or not fully seated. Move it to the top CPU-attached x16 slot. (Link SPEED drops at idle - that is normal; WIDTH should not.)' }
    if ($g.Name -match 'Microsoft Basic Display') { Add-Finding 'HIGH' 'GPU' 'No vendor GPU driver installed (Microsoft Basic Display Adapter)' 'Install the GPU driver from NVIDIA/AMD/Intel' }
}
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $q = TryGet { & nvidia-smi --query-gpu=name,driver_version,pcie.link.gen.gpucurrent,pcie.link.gen.max,pcie.link.gen.hostmax,pcie.link.width.current,pcie.link.width.max,temperature.gpu --format=csv,noheader 2>$null }
    if ($q) { $S.NvidiaSmi = $q; $p = $q -split ',\s*'; $bar = TryGet { (& nvidia-smi -q 2>$null | Select-String -Pattern 'BAR1 Memory Usage' -Context 0,1).Context.PostContext[0] }; $S.NvidiaBAR1 = "$bar"
        if ("$bar" -match '(\d+)\s*MiB' -and [int]$Matches[1] -le 256) { Add-Finding 'MED' 'BIOS' 'Resizable BAR is OFF (BAR1 = 256 MiB)' 'BIOS: Above 4G Decoding = On, Re-Size BAR = On (needs CSM off)' }
        if ($p.Count -ge 5 -and [int]$p[4] -lt [int]$p[3]) { Add-Finding 'MED' 'GPU' "PCIe generation capped by host: host max Gen$($p[4]) vs GPU Gen$($p[3])" 'Check slot (chipset slots are often Gen3) and BIOS PCIe link speed (Auto)' } }
}
$cur = [PCOptDisplay]::Current(); $max = [PCOptDisplay]::MaxHz($cur[0], $cur[1])
$S.Display = [ordered]@{ Resolution = "$($cur[0])x$($cur[1])"; CurrentHz = $cur[2]; MaxHz = $max; ModesHz = [PCOptDisplay]::Modes($cur[0], $cur[1]) }
$S.Monitors = @(TryGet { Get-CimInstance -Namespace root\wmi WmiMonitorID -ErrorAction Stop | ForEach-Object { ([char[]]($_.ManufacturerName -ne 0) -join '') + ' ' + ([char[]]($_.UserFriendlyName -ne 0) -join '') } })
if ($max -gt 0 -and $cur[2] -lt $max - 1) { Add-Finding 'HIGH' 'Display' "Display runs at $($cur[2]) Hz but supports $max Hz" 'Set-Display.ps1 -Mode Apply (or Settings > Display > Advanced display)' }
$hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode
$S.HAGS = if ($null -eq $hags) { 'default' } elseif ($hags -eq 2) { 'on' } else { 'off' }

# ---------------- Storage ----------------
$S.Disks = @(Get-PhysicalDisk | ForEach-Object {
    $o = [ordered]@{ Name = $_.FriendlyName; Media = "$($_.MediaType)"; Bus = "$($_.BusType)"; GB = [math]::Round($_.Size/1GB); Health = "$($_.HealthStatus)"; Firmware = $_.FirmwareVersion }
    if ($admin) { $r = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; if ($r) { $o.TempC = $r.Temperature; $o.WearPct = $r.Wear; $o.PowerOnHours = $r.PowerOnHours; $o.ReadErrors = $r.ReadErrorsTotal; $o.WriteErrors = $r.WriteErrorsTotal } }
    $o })
foreach ($d in $S.Disks) { if ($d.Health -ne 'Healthy') { Add-Finding 'HIGH' 'Storage' "$($d.Name) health = $($d.Health)" 'Back up data now; check SMART' }; if ($d.WearPct -ge 80) { Add-Finding 'MED' 'Storage' "$($d.Name) wear $($d.WearPct)%" 'Plan replacement' } }
$S.Volumes = @(Get-Volume | Where-Object DriveLetter | ForEach-Object { [ordered]@{ Drive = $_.DriveLetter; Label = $_.FileSystemLabel; FS = $_.FileSystem; SizeGB = [math]::Round($_.Size/1GB,1); FreeGB = [math]::Round($_.SizeRemaining/1GB,1) } })
foreach ($v in $S.Volumes) { if ($v.SizeGB -gt 50 -and $v.FreeGB / $v.SizeGB -lt 0.15) { Add-Finding 'MED' 'Storage' "Drive $($v.Drive): only $($v.FreeGB) GB free" 'Free space (keep >15% on SSDs)' } }
$S.TRIM = (& fsutil behavior query DisableDeleteNotify 2>$null | Select-Object -First 1)
if ($S.TRIM -match 'NTFS DisableDeleteNotify = 1') { Add-Finding 'MED' 'Storage' 'TRIM is disabled' 'fsutil behavior set DisableDeleteNotify 0 (admin)' }
if (@(Get-Disk | Where-Object BusType -eq 'USB').Count) { Add-Finding 'INFO' 'Storage' 'A USB storage device is connected (install media?)' 'Unplug the installer USB when done' }

# ---------------- Devices / drivers ----------------
$S.ProblemDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object { [ordered]@{ Name = $_.Name; Code = $_.ConfigManagerErrorCode; Id = $_.DeviceID } })
foreach ($p in $S.ProblemDevices) { $hint = if ($p.Id -match 'VEN_8086') { 'Intel chipset INF / Serial IO / MEI from the board vendor' } elseif ($p.Id -match 'VEN_1022') { 'AMD chipset driver' } else { 'Board vendor support page' }; Add-Finding 'HIGH' 'Drivers' "Device without working driver: $($p.Name) (Code $($p.Code)) $($p.Id)" $hint }
$drv = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -and $_.DeviceClass -in 'NET','MEDIA','DISPLAY','SYSTEM','HDC','SCSIADAPTER','BLUETOOTH','USB' })
$S.KeyDrivers = @($drv | Where-Object { $_.DriverProviderName -notmatch '^Microsoft' -or $_.DeviceClass -in 'NET','DISPLAY' } | Sort-Object DeviceClass, DeviceName -Unique | ForEach-Object { [ordered]@{ Class = $_.DeviceClass; Device = $_.DeviceName; Provider = $_.DriverProviderName; Version = $_.DriverVersion; Date = if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } } })
foreach ($n in ($drv | Where-Object { $_.DeviceClass -eq 'NET' -and $_.DeviceName -match 'Realtek|Intel\(R\) Ethernet|Killer|Aquantia|Marvell' })) { if ($n.DriverProviderName -match 'Microsoft' -or ($n.DriverDate -and $n.DriverDate -lt (Get-Date).AddYears(-3))) { Add-Finding 'MED' 'Drivers' "$($n.DeviceName) uses an old/inbox driver ($($n.DriverVersion), $($n.DriverDate.ToString('yyyy-MM-dd')))" 'Install the vendor LAN driver from the board support page' } }
foreach ($a in ($drv | Where-Object { $_.DeviceName -eq 'High Definition Audio Device' })) { Add-Finding 'LOW' 'Drivers' 'Onboard audio uses the generic Microsoft HDA driver' 'Optional: vendor (Realtek) audio driver if you use the board jacks' }

# ---------------- Security ----------------
$dg = TryGet { Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop }
$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
$sh = New-Object -ComObject Shell.Application
$bl = TryGet { $sh.NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection') }
$mp = TryGet { Get-MpComputerStatus -ErrorAction Stop }
$S.Security = [ordered]@{ SecureBoot = $sb; VBS = $dg.VirtualizationBasedSecurityStatus; HVCI = (@($dg.SecurityServicesRunning) -contains 2); BitLockerC = $bl; DefenderRealtime = $mp.RealTimeProtectionEnabled; AV = @(TryGet { (Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop).displayName }) }
if ($admin) { $S.Security.TPM = TryGet { (Get-Tpm).TpmReady }; $S.Security.SecureBootConfirm = TryGet { Confirm-SecureBootUEFI } }
$uefi = (& bcdedit /enum '{current}' 2>$null | Select-String 'winload.efi') -ne $null
$gpt = -not @(Get-Disk | Where-Object { $_.BootFromDisk -or $_.IsSystem } | Where-Object PartitionStyle -ne 'GPT').Count
if ($sb -ne 1) { Add-Finding 'MED' 'Security' "Secure Boot is OFF (BitLocker C: = $bl; 1=on 2=off)" 'BIOS: CSM off + Secure Boot OS Type = Windows UEFI. If BitLocker is ON, get the recovery key first.' }
if ($mp -and -not $mp.RealTimeProtectionEnabled) { Add-Finding 'HIGH' 'Security' 'Defender real-time protection is OFF' 'Turn it on unless another AV is active' }

# ---------------- Power / input / gaming ----------------
$S.PowerPlan = (& powercfg /getactivescheme) -replace '.*\(|\).*',''
$S.FastStartup = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled
$m = Get-ItemProperty 'HKCU:\Control Panel\Mouse'
$S.MouseAccel = ($m.MouseSpeed -ne '0')
if ($S.MouseAccel) { Add-Finding 'LOW' 'Input' 'Enhance pointer precision (mouse acceleration) is ON' 'Set-Mouse.ps1 -Mode Apply (preference; raw-input games ignore it)' }
$S.GameMode = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled
$S.DirectXUserGlobalSettings = (Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue).DirectXUserGlobalSettings
$S.HIDDevices = @(Get-PnpDevice -PresentOnly -Class Mouse, Keyboard -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Class): $(([regex]::Match($_.InstanceId, 'VID_[0-9A-F]{4}&PID_[0-9A-F]{4}')).Value)" } | Sort-Object -Unique)

# ---------------- Network ----------------
$S.Network = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ Name = $_.Name; Desc = $_.InterfaceDescription; Status = "$($_.Status)"; Link = $_.LinkSpeed; Driver = $_.DriverVersion } })
$S.DNS = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object ServerAddresses | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" })

# ---------------- Software / startup / services ----------------
$S.Startup = @(Get-CimInstance Win32_StartupCommand | ForEach-Object { "$($_.Name) | $($_.Command)" })
$S.InstalledApps = @(Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object DisplayName | Sort-Object DisplayName -Unique | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" })
foreach ($bad in 'Driver Easy','Driver Booster','DriverPack','CCleaner','Advanced SystemCare','Razer Cortex','Wise Game Booster') { if ($S.InstalledApps -match [regex]::Escape($bad)) { Add-Finding 'MED' 'Software' "$bad is installed" 'Driver updaters / "boosters" install non-vendor drivers or add background load - uninstall' } }
$S.ThirdPartyServices = @(Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64)\\(svchost|lsass)' -and $_.PathName -notmatch 'Windows Defender|Microsoft' } | ForEach-Object { "$($_.Name) ($($_.StartMode))" })
$S.ProcessCount = (Get-Process).Count

# ---------------- Stability / events ----------------
$since = (Get-Date).AddDays(-7)
$whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue)
$S.WHEA7d = @($whea | Group-Object Id | ForEach-Object { "Id $($_.Name) x$($_.Count)" })
$fatalWhea = @($whea | Where-Object { $_.Id -in 1, 18, 19, 20, 46, 47 })
if ($fatalWhea.Count) { Add-Finding 'HIGH' 'Stability' "$($fatalWhea.Count) serious WHEA hardware errors in 7 days (CPU/RAM/PCIe)" 'Undo overclock/XMP, run memory + CPU stress tests' }
$crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue | ForEach-Object { $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }; [pscustomobject]@{ Time = $_.TimeCreated; Bugcheck = [int64]$d.BugcheckCode; PowerButton = ($d.PowerButtonTimestamp -ne '0'); SleepInProgress = $d.SleepInProgress } })
$S.UncleanShutdowns7d = @($crashes | ForEach-Object { "$($_.Time) bugcheck=0x{0:X} powerButton={1} sleep={2}" -f $_.Bugcheck, $_.PowerButton, $_.SleepInProgress })
$bsod = @($crashes | Where-Object { $_.Bugcheck -ne 0 })
if ($bsod.Count) { Add-Finding 'HIGH' 'Stability' "$($bsod.Count) blue-screen crash(es) in 7 days" 'Check C:\Windows\Minidump; test RAM/XMP' }
$S.Minidumps = @(Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) $($_.LastWriteTime)" })
if ($admin) {
    $S.BootTimesMs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 3 -ErrorAction SilentlyContinue | ForEach-Object { $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }; "$($_.TimeCreated): boot $($d.BootTime) ms (main $($d.MainPathBootTime), post $($d.BootPostBootTime))" })
    $S.FwPOSTms = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).FwPOSTTime
}

# ---------------- Summary ----------------
if ($S.PowerPlan -match 'Power saver') { Add-Finding 'MED' 'Power' 'Power saver plan is active on a desktop' 'Use Balanced (default) or High performance' }
Add-Finding 'INFO' 'Gaming' "Game Mode=$(if ($null -eq $S.GameMode) {'default(on)'} else {$S.GameMode}); HAGS=$($S.HAGS); PowerPlan=$($S.PowerPlan); FastStartup=$($S.FastStartup)" 'Keep Game Mode + HAGS on (defaults)'
$order = @{ HIGH = 0; MED = 1; LOW = 2; INFO = 3 }
$S.Findings = @($F | Sort-Object { $order[$_.Severity] })
$json = Join-Path $OutDir "scan-$stamp.json"
$S | ConvertTo-Json -Depth 6 | Out-File $json -Encoding utf8

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# PC scan $stamp  (admin: $admin)")
[void]$md.AppendLine("`n## Hardware`n- CPU: $($S.CPU.Name) ($($S.CPU.Cores)C/$($S.CPU.Threads)T)`n- Board: $($S.Board.Manufacturer) $($S.Board.Product), BIOS $($S.Board.BIOS) ($($S.Board.BIOSDate))")
[void]$md.AppendLine("- RAM: $($S.RAMTotalGB) GB, configured $cfg MT/s, rated (from part no.) $(if ($rated) {$rated} else {'unknown'}) - $(($S.RAM | ForEach-Object { "$($_.Slot) $($_.Part)" }) -join '; ')")
foreach ($g in $S.GPU) { [void]$md.AppendLine("- GPU: $($g.Name), driver $($g.Driver), PCIe x$($g.CurrentLinkWidth)/x$($g.MaxLinkWidth), parent: $($g.ParentPort)") }
[void]$md.AppendLine("- Display: $($S.Display.Resolution) @ $($S.Display.CurrentHz) Hz (max $($S.Display.MaxHz)); monitors: $($S.Monitors -join ', ')")
foreach ($d in $S.Disks) { [void]$md.AppendLine("- Disk: $($d.Name) $($d.Media) $($d.Bus) $($d.GB) GB, $($d.Health)$(if ($d.TempC) {", $($d.TempC) C, wear $($d.WearPct)%"})") }
[void]$md.AppendLine("- Security: SecureBoot=$sb, VBS=$($S.Security.VBS), HVCI=$($S.Security.HVCI), BitLocker(C:)=$bl, AV=$($S.Security.AV -join ', ')")
[void]$md.AppendLine("`n## Findings (most important first)`n| Sev | Area | Finding | Suggested |`n|---|---|---|---|")
foreach ($x in $S.Findings) { [void]$md.AppendLine("| $($x.Severity) | $($x.Area) | $($x.Finding -replace '\|','/') | $($x.Suggested -replace '\|','/') |") }
if (-not $admin) { [void]$md.AppendLine("`n_Not elevated: SMART, TPM, Secure Boot confirm and boot times were skipped._") }
$mdFile = Join-Path $OutDir "scan-$stamp.md"
$md.ToString() | Out-File $mdFile -Encoding utf8
Write-Output "Scan written: $mdFile"
Write-Output $md.ToString()
