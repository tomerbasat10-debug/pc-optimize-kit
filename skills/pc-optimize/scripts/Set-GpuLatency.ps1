# Set-GpuLatency.ps1 - low-latency graphics settings. Run ELEVATED (NVIDIA driver profile write).
#  - Windows "Optimizations for windowed games" (flip model) on; Windows VRR optimization follows -GSync
#  - NVIDIA (via NVIDIA Profile Inspector, Base Profile): Max pre-rendered frames = 1 (= Low Latency Mode On); G-SYNC global on/off/unchanged
# Setting IDs are from NVIDIA's public NvApiDriverSettings.h and are VERIFIED after import by re-exporting what the driver reports.
param([ValidateSet('Apply','Revert')][string]$Mode = 'Apply', [ValidateSet('Keep','On','Off')][string]$GSync = 'Keep')
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$npi = Join-Path $root 'tools\NPI\nvidiaProfileInspector.exe'
$dxPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$state = Join-Path $root 'backups\gpu-latency-previous.json'
$PRERENDER = 0x007BA09E; $VRR_MODE = 0x1194F158   # VRR_MODE: 0 off, 1 fullscreen only (default), 2 fullscreen+windowed

function Write-Nip($path, $settings) {
    $x = '<?xml version="1.0" encoding="utf-16"?>' + "`r`n<ArrayOfProfile>`r`n  <Profile>`r`n    <ProfileName>Base Profile</ProfileName>`r`n    <Executeables />`r`n    <Settings>`r`n"
    foreach ($s in $settings) { $x += "      <ProfileSetting>`r`n        <SettingNameInfo>$($s.Name)</SettingNameInfo>`r`n        <SettingID>$($s.Id)</SettingID>`r`n        <SettingValue>$($s.Value)</SettingValue>`r`n        <ValueType>Dword</ValueType>`r`n      </ProfileSetting>`r`n" }
    $x += "    </Settings>`r`n  </Profile>`r`n</ArrayOfProfile>`r`n"
    [IO.File]::WriteAllText($path, $x, [Text.Encoding]::Unicode)
}
function Export-Npi { $d = Split-Path $npi; Get-ChildItem $d -Filter 'CustomProfiles_*.nip' | Remove-Item -ErrorAction SilentlyContinue; Start-Process $npi -ArgumentList '-exportCustomized' -WorkingDirectory $d -Wait; Get-ChildItem $d -Filter 'CustomProfiles_*.nip' | Sort-Object LastWriteTime | Select-Object -Last 1 }
$isNv = [bool](Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA')

if ($Mode -eq 'Apply') {
    $prevDx = (Get-ItemProperty $dxPath -ErrorAction SilentlyContinue).DirectXUserGlobalSettings
    $exp = $null; if ($isNv -and (Test-Path $npi)) { $exp = Export-Npi; if ($exp) { Copy-Item $exp.FullName (Join-Path $root 'backups\nvidia-before.nip') -Force } }
    @{ DX = $prevDx } | ConvertTo-Json | Out-File $state -Encoding utf8
    Backup-RegKey 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'dx-userprefs' | Out-Null
    $vrr = if ($GSync -eq 'Off') { 0 } else { 1 }
    New-Item -Path $dxPath -Force | Out-Null
    Set-ItemProperty $dxPath -Name DirectXUserGlobalSettings -Value "SwapEffectUpgradeEnable=1;VRROptimizeEnable=$vrr;"
    Add-Journal 'GPU-DX' "DirectXUserGlobalSettings '$prevDx' -> 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=$vrr;'" "& `"$PSCommandPath`" -Mode Revert"
    if ($isNv) {
        if (-not (Test-Path $npi)) { Write-Warning 'NVIDIA Profile Inspector missing (Install-Tools.ps1 -Components NPI) - NVIDIA part skipped'; return }
        $set = @(@{ Name = 'Maximum pre-rendered frames'; Id = $PRERENDER; Value = 1 })
        if ($GSync -eq 'Off') { $set += @{ Name = 'G-SYNC - Global Mode'; Id = $VRR_MODE; Value = 0 } }
        if ($GSync -eq 'On')  { $set += @{ Name = 'G-SYNC - Global Mode'; Id = $VRR_MODE; Value = 2 } }
        $nip = Join-Path $root 'backups\nvidia-apply.nip'; Write-Nip $nip $set
        Start-Process $npi -ArgumentList '-silentImport', "`"$nip`"" -WorkingDirectory (Split-Path $npi) -Wait
        $v = Export-Npi; if ($v) { Copy-Item $v.FullName (Join-Path $root 'backups\nvidia-after.nip') -Force; '--- driver now reports:'; Select-String -Path $v.FullName -Pattern 'SettingNameInfo|SettingValue' | ForEach-Object { $_.Line.Trim() } }
        Add-Journal 'GPU-NV' "NVIDIA Base Profile: pre-rendered frames=1 (Low Latency On); G-SYNC=$GSync" "& `"$PSCommandPath`" -Mode Revert"
        'In games: NVIDIA Reflex On (+Boost) where available; V-Sync OFF in game when G-SYNC is off.'
    }
} else {
    $prev = (Get-Content $state -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json).DX
    if ($prev) { Set-ItemProperty $dxPath -Name DirectXUserGlobalSettings -Value $prev } else { Remove-ItemProperty $dxPath -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue }
    Write-Log "REVERT GPU-DX -> '$prev'"
    if ($isNv -and (Test-Path $npi)) {
        $nip = Join-Path $root 'backups\nvidia-revert.nip'
        Write-Nip $nip @(@{ Name = 'Maximum pre-rendered frames'; Id = $PRERENDER; Value = 0 }, @{ Name = 'G-SYNC - Global Mode'; Id = $VRR_MODE; Value = 1 })
        Start-Process $npi -ArgumentList '-silentImport', "`"$nip`"" -WorkingDirectory (Split-Path $npi) -Wait
        Write-Log 'REVERT GPU-NV: pre-render app-controlled, G-SYNC fullscreen-only (driver defaults). Alternative: NVIDIA Control Panel > Manage 3D settings > Restore'
    }
}
