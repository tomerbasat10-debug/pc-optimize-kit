# Revert-All.ps1 - undo every journaled change, newest first. Run ELEVATED. Use -WhatIf to list only, -Id to revert one item.
param([switch]$WhatIf, [string]$Id)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$j = Join-Path $root 'journal.jsonl'
if (-not (Test-Path $j)) { 'No journal - nothing to revert.'; return }
$entries = @(Get-Content $j | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
[array]::Reverse($entries)
foreach ($e in $entries) {
    if ($e.Reverted) { continue }
    if ($Id -and $e.Id -ne $Id) { continue }
    "[$($e.Time)] $($e.Id): $($e.Description)`n    -> $($e.RevertCommand)"
    if ($WhatIf) { continue }
    try { Invoke-Expression $e.RevertCommand; $e.Reverted = $true; Write-Log "REVERTED [$($e.Id)]" } catch { Write-Warning "Revert of $($e.Id) failed: $($_.Exception.Message)" }
}
if (-not $WhatIf) { [array]::Reverse($entries); $entries | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content $j -Encoding utf8 }
'BIOS changes (XMP, Secure Boot, ...) are not journaled - revert them in BIOS (load your saved "stock" profile).'
