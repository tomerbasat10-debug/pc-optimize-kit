# Measure-Baseline.ps1 - READ-ONLY baseline/after measurements. Run ELEVATED for WinSAT + boot time.
# Collects: idle CPU/RAM/DPC counters (60 s), WinSAT cpu/mem/disk (D3D test is deprecated - skipped), boot time,
# optional Cinebench R23 (-Cinebench, ~15 min, PC must be idle). Writes baseline\<Tag>\baseline.json
param([string]$Tag = 'before', [switch]$Cinebench)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$dir = Join-Path $root "baseline\$Tag"; New-Item -ItemType Directory -Force $dir | Out-Null
$B = [ordered]@{ Tag = $Tag; Time = (Get-Date -Format 's') }

$c = Get-Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes','\Processor(_Total)\% DPC Time','\Processor(_Total)\% Interrupt Time' -SampleInterval 2 -MaxSamples 30
$g = $c.CounterSamples | Group-Object Path
$B.IdleCpuPct = [math]::Round((($g | Where-Object Name -match 'processor time').Group.CookedValue | Measure-Object -Average).Average, 2)
$B.IdleRamUsedGB = [math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1MB - (($g | Where-Object Name -match 'available').Group.CookedValue | Measure-Object -Average).Average)/1024, 2)
$B.DpcTimePct = [math]::Round((($g | Where-Object Name -match 'dpc time').Group.CookedValue | Measure-Object -Average).Average, 3)
$B.Processes = (Get-Process).Count; $B.RunningServices = @(Get-Service | Where-Object Status -eq Running).Count
$B.Note = 'Idle numbers include whatever is open (e.g. the Claude app) - keep conditions identical for before/after.'

if (Test-Admin) {
    foreach ($t in @(@{n='cpu';a='cpuformal'}, @{n='mem';a='mem'}, @{n='diskseq';a='disk -drive c -seq -read'}, @{n='diskran';a='disk -drive c -ran -read'})) {
        $out = cmd /c "winsat $($t.a) 2>&1"
        $B["WinSAT_$($t.n)"] = @($out | Select-String -Pattern '> (CPU|Memory Performance|Disk  )' | ForEach-Object { ($_.Line -replace '^>\s*','').Trim() })
    }
    $B.BootMs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction SilentlyContinue | ForEach-Object { $d=@{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }; [int]$d.BootTime })[0]
    $B.FwPOSTms = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).FwPOSTTime
}

if ($Cinebench) {
    $cb = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter Cinebench.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    if ($cb) {
        foreach ($t in @(@{n='Multi';a='g_CinebenchCpuXTest=true'}, @{n='Single';a='g_CinebenchCpu1Test=true'})) {
            $o = Join-Path $dir "cinebench-$($t.n).txt"
            # NOTE: R23 keeps its window open after finishing; closing it early loses the score. It exits on its own in autorun mode.
            Start-Process $cb -ArgumentList $t.a -RedirectStandardOutput $o -Wait -WindowStyle Minimized
            $B["Cinebench$($t.n)"] = (Select-String -Path $o -Pattern '^CB\s+([\d\.]+)' | Select-Object -Last 1).Matches.Groups[1].Value
            if (-not $B["Cinebench$($t.n)"]) { $B["Cinebench$($t.n)"] = (Select-String -Path $o -Pattern 'Avg/Deviation:\s*([\d\.]+)' | Select-Object -Last 1).Matches.Groups[1].Value }
        }
    } else { $B.Cinebench = 'not installed (Install-Tools.ps1 -Components Bench)' }
}
$B | ConvertTo-Json -Depth 4 | Out-File (Join-Path $dir 'baseline.json') -Encoding utf8
$B | ConvertTo-Json -Depth 4
