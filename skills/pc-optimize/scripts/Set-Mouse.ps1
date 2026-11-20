# Set-Mouse.ps1 - turn "Enhance pointer precision" (mouse acceleration) off / back on. No admin needed. Applies live.
param([ValidateSet('Apply','Revert','Show')][string]$Mode = 'Show')
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
if (-not ('PCOptMouse' -as [type])) { Add-Type 'using System; using System.Runtime.InteropServices; public static class PCOptMouse { [DllImport("user32.dll")] public static extern bool SystemParametersInfo(int a, int p, int[] v, int f); }' }
$state = Join-Path $root 'backups\mouse-previous.txt'
$m = Get-ItemProperty 'HKCU:\Control Panel\Mouse'
switch ($Mode) {
  'Show'   { "MouseSpeed=$($m.MouseSpeed) Threshold1=$($m.MouseThreshold1) Threshold2=$($m.MouseThreshold2)  (acceleration " + $(if ($m.MouseSpeed -ne '0') {'ON'} else {'OFF'}) + ')' }
  'Apply'  {
    if ($m.MouseSpeed -eq '0') { 'Acceleration already off'; return }
    Backup-RegKey 'HKCU\Control Panel\Mouse' 'mouse' | Out-Null
    Set-Content $state "$($m.MouseThreshold1),$($m.MouseThreshold2),$($m.MouseSpeed)"
    [void][PCOptMouse]::SystemParametersInfo(0x0004, 0, [int[]](0,0,0), 3)
    Add-Journal 'MOUSE' 'Enhance pointer precision OFF' "& `"$PSCommandPath`" -Mode Revert"
  }
  'Revert' { $p = (Get-Content $state -ErrorAction SilentlyContinue) -split ','; if ($p.Count -ne 3) { $p = 6,10,1 }; [void][PCOptMouse]::SystemParametersInfo(0x0004, 0, [int[]]($p | ForEach-Object { [int]$_ }), 3); Write-Log "REVERT MOUSE -> $($p -join ',')" }
}
