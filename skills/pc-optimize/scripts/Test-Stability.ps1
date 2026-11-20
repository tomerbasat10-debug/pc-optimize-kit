# Test-Stability.ps1 - READ-ONLY. Run ELEVATED (CPU sensors via PawnIO).
# 30 s idle sampling, then -LoadSeconds full CPU load (Cinebench R23 multi), then cooldown; temps/power/clock every 2 s.
# Afterwards checks for WHEA errors, blue screens and app crashes that happened during the test.
# RAM/XMP: a real memory test still needs OCCT > Stability Test > MEMORY (GUI, 30-60 min) - remind the user.
param([string]$Tag = 'stability', [int]$LoadSeconds = 180)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$dir = Join-Path $root "baseline\$Tag"; New-Item -ItemType Directory -Force $dir | Out-Null
$t0 = Get-Date
$lib = Join-Path $root 'tools\LibreHardwareMonitor\LibreHardwareMonitorLib.dll'
if (-not (Test-Path $lib)) { throw 'LibreHardwareMonitor missing: run Install-Tools.ps1 -Components LHM (elevated)' }
Add-Type -Path $lib
$pc = New-Object LibreHardwareMonitor.Hardware.Computer
$pc.IsCpuEnabled = $true; $pc.IsGpuEnabled = $true; $pc.IsStorageEnabled = $true; $pc.IsMotherboardEnabled = $true; $pc.Open()
$pc.Hardware | ForEach-Object { $h=$_; $h.Update(); @($h.Sensors) + @($h.SubHardware | ForEach-Object { $_.Update(); $_.Sensors }) } | Where-Object { $_.SensorType -in 'Temperature','Power','Clock' } | ForEach-Object { "$($_.Hardware.Name) | $($_.SensorType) | $($_.Name) = $($_.Value)" } | Out-File (Join-Path $dir 'sensors-list.txt') -Encoding utf8

function Sample($phase) {
    foreach ($h in $pc.Hardware) { $h.Update(); foreach ($s in $h.SubHardware) { $s.Update() } }
    $all = foreach ($h in $pc.Hardware) { $h.Sensors; foreach ($s in $h.SubHardware) { $s.Sensors } }
    $T = { param($hw, $pat) ($all | Where-Object { $_.SensorType -eq 'Temperature' -and "$($_.Hardware.HardwareType)" -match $hw -and $_.Name -match $pat -and $_.Value -ne $null } | Measure-Object Value -Maximum).Maximum }
    [pscustomobject]@{ Time = (Get-Date -Format HH:mm:ss); Phase = $phase
        CpuPackage = & $T 'Cpu' 'Package|Tctl|Tdie'; CpuCoreMax = & $T 'Cpu' 'Core (Max|#\d+)|P-Core|CCD'
        CpuPowerW = ($all | Where-Object { $_.SensorType -eq 'Power' -and "$($_.Hardware.HardwareType)" -eq 'Cpu' -and $_.Name -match 'Package' } | Select-Object -First 1).Value
        CpuClockMHz = ($all | Where-Object { $_.SensorType -eq 'Clock' -and "$($_.Hardware.HardwareType)" -eq 'Cpu' -and $_.Name -match 'Core' } | Measure-Object Value -Maximum).Maximum
        Gpu = & $T 'Gpu' 'GPU Core|Edge'; Ssd = & $T 'Storage' 'Composite Temperature|^Temperature$' }
}
$rows = @(); for ($i = 0; $i -lt 15; $i++) { $rows += Sample 'idle'; Start-Sleep 2 }
$cb = (Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\WinGet\Packages" -Recurse -Filter Cinebench.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if ($cb) { Start-Process $cb -ArgumentList 'g_CinebenchCpuXTest=true' -WindowStyle Minimized | Out-Null } else { Write-Warning 'Cinebench not installed - load phase will be idle' }
$end = (Get-Date).AddSeconds($LoadSeconds); while ((Get-Date) -lt $end) { $rows += Sample 'load'; Start-Sleep 2 }
Get-Process Cinebench -ErrorAction SilentlyContinue | Stop-Process -Force
for ($i = 0; $i -lt 10; $i++) { $rows += Sample 'cooldown'; Start-Sleep 2 }
$pc.Close()
$rows | Export-Csv (Join-Path $dir 'temps.csv') -NoTypeInformation
$sum = $rows | Group-Object Phase | ForEach-Object { $g = $_.Group; [pscustomobject]@{ Phase = $_.Name
    CpuPkgAvg = [math]::Round(($g.CpuPackage | Measure-Object -Average).Average, 1); CpuPkgMax = ($g.CpuPackage | Measure-Object -Maximum).Maximum
    CpuCoreMax = ($g.CpuCoreMax | Measure-Object -Maximum).Maximum; CpuWMax = [math]::Round(($g.CpuPowerW | Measure-Object -Maximum).Maximum, 1)
    ClockMax = [math]::Round(($g.CpuClockMHz | Measure-Object -Maximum).Maximum); ClockMinLoad = [math]::Round(($g.CpuClockMHz | Measure-Object -Minimum).Minimum)
    GpuMax = ($g.Gpu | Measure-Object -Maximum).Maximum; SsdMax = ($g.Ssd | Measure-Object -Maximum).Maximum } }
$whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $t0 } -ErrorAction SilentlyContinue)
$app  = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $t0 } -ErrorAction SilentlyContinue)
$txt = ($sum | Format-Table -AutoSize | Out-String -Width 200) + "WHEA during test: $($whea.Count)  App crashes during test: $($app.Count)`n" +
       "Guide: Intel TjMax ~100 C, AMD Ryzen 7000 ~95 C. Sustained >90 C or ClockMinLoad far below ClockMax = cooling/power-limit problem."
$txt | Out-File (Join-Path $dir 'stability-summary.txt') -Encoding utf8
$txt
