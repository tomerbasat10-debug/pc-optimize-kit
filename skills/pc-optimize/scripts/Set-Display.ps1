# Set-Display.ps1 - set primary display to the highest refresh rate at the current resolution. No admin needed.
param([ValidateSet('Apply','Revert','Show')][string]$Mode = 'Show', [int]$Hz = 0)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$state = Join-Path $root 'backups\display-previous.txt'
$c = [PCOptDisplay]::Current()
switch ($Mode) {
  'Show'   { "Current $($c[0])x$($c[1]) @ $($c[2]) Hz; available: $([PCOptDisplay]::Modes($c[0],$c[1])) Hz" }
  'Apply'  {
    $target = if ($Hz) { $Hz } else { [PCOptDisplay]::MaxHz($c[0], $c[1]) }
    if ($c[2] -ge $target) { "Already at $($c[2]) Hz - nothing to do"; return }
    if (-not (Test-Path $state)) { Set-Content $state "$($c[2])" }
    $r = [PCOptDisplay]::SetHz($target)
    if ($r -eq 0) { Add-Journal 'DISPLAY' "Refresh $($c[2]) -> $target Hz" "& `"$PSCommandPath`" -Mode Revert"; "OK: now $(([PCOptDisplay]::Current())[2]) Hz" } else { "FAILED (code $r)" }
  }
  'Revert' { $prev = [int](Get-Content $state -ErrorAction SilentlyContinue); if (-not $prev) { $prev = 60 }; $r = [PCOptDisplay]::SetHz($prev); Write-Log "REVERT DISPLAY -> $prev Hz (result $r)"; Remove-Item $state -ErrorAction SilentlyContinue }
}
