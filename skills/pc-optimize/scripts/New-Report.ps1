# New-Report.ps1 - build FINAL-REPORT.md: every journaled change + before/after comparison of baseline JSON, DPC and stability summaries.
param([string]$Before = 'before', [string]$After = 'after')
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$sb = New-Object System.Text.StringBuilder
$scan = Get-ChildItem (Join-Path $root 'scan') -Filter 'scan-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
[void]$sb.AppendLine("# PC optimization report - $(Get-Date -Format 'yyyy-MM-dd')`n")
if ($scan) { $s = Get-Content $scan.FullName -Raw | ConvertFrom-Json; [void]$sb.AppendLine("System: $($s.CPU.Name) | $($s.Board.Manufacturer) $($s.Board.Product) BIOS $($s.Board.BIOS) | $($s.RAMTotalGB) GB RAM | $(($s.GPU | ForEach-Object Name) -join ', ') | $($s.OS.Caption) $($s.OS.Version) ($($s.OS.Build))`n") }
[void]$sb.AppendLine("## Changes (undo: scripts\Revert-All.ps1, elevated)`n| Time | Id | Change | Undo |`n|---|---|---|---|")
$j = Join-Path $root 'journal.jsonl'
if (Test-Path $j) {
    foreach ($line in (Get-Content $j | Where-Object { $_.Trim() })) {
        $e = $line | ConvertFrom-Json
        $undo = if ($e.Reverted) { 'REVERTED' } else { '`' + ($e.RevertCommand -replace '\|','/') + '`' }
        $desc = $e.Description -replace '\|','/'
        [void]$sb.AppendLine("| $($e.Time) | $($e.Id) | $desc | $undo |")
    }
}
$bf = Join-Path $root "baseline\$Before\baseline.json"; $af = Join-Path $root "baseline\$After\baseline.json"
if ((Test-Path $bf) -and (Test-Path $af)) {
    $b = Get-Content $bf -Raw | ConvertFrom-Json; $a = Get-Content $af -Raw | ConvertFrom-Json
    [void]$sb.AppendLine("`n## Before / after`n| Metric | $Before | $After |`n|---|---|---|")
    foreach ($p in $b.PSObject.Properties.Name | Where-Object { $_ -notin 'Tag','Time','Note' }) { [void]$sb.AppendLine("| $p | $(@($b.$p) -join '; ') | $(@($a.$p) -join '; ') |") }
}
foreach ($t in $Before, $After) { foreach ($f in 'dpc-summary.txt','stability-summary.txt') { $p = Join-Path $root "baseline\$t\$f"; if (Test-Path $p) { [void]$sb.AppendLine("`n### $t - $f`n``````"); [void]$sb.AppendLine((Get-Content $p -Raw)); [void]$sb.AppendLine('```') } } }
$out = Join-Path $root 'FINAL-REPORT.md'; $sb.ToString() | Out-File $out -Encoding utf8
"Report: $out"
