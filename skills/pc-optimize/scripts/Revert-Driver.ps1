# Revert-Driver.ps1 - remove driver packages added between two pnputil snapshots, then re-add the exported originals. ELEVATED. Reboot afterwards.
param([Parameter(Mandatory)][string]$Before, [Parameter(Mandatory)][string]$After, [string]$Backup)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$b = Select-String -Path $Before -Pattern '(oem\d+\.inf)' | ForEach-Object { $_.Matches[0].Value } | Sort-Object -Unique
$a = Select-String -Path $After  -Pattern '(oem\d+\.inf)' | ForEach-Object { $_.Matches[0].Value } | Sort-Object -Unique
foreach ($inf in ($a | Where-Object { $_ -notin $b })) { Write-Log "REVERT DRIVER: removing $inf"; & pnputil.exe /delete-driver $inf /uninstall /force }
if ($Backup -and (Test-Path $Backup)) { Write-Log "REVERT DRIVER: re-adding originals from $Backup"; & pnputil.exe /add-driver (Join-Path $Backup '*.inf') /subdirs /install | Select-Object -Last 3 }
'Reboot to finish. Per-device alternative: Device Manager > device > Driver > Roll Back Driver.'
