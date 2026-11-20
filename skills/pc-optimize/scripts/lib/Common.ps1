# Common.ps1 - shared helpers for pc-optimize-kit. Dot-source:  . "$PSScriptRoot\lib\Common.ps1"
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI and non-ASCII breaks parsing.

$ErrorActionPreference = 'Continue'
if (-not $env:PCOPT_ROOT) { $env:PCOPT_ROOT = 'C:\PCOptimize' }
$script:Root = $env:PCOPT_ROOT

function Initialize-Workspace {
    foreach ($d in 'logs','backups','baseline','tools','downloads') { New-Item -ItemType Directory -Force (Join-Path $script:Root $d) | Out-Null }
    return $script:Root
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -Path (Join-Path $script:Root 'logs\changes.log') -Value $line -Encoding utf8
    Write-Output $Message
}

# Journal: one JSON object per line. Revert-All.ps1 replays RevertCommand in reverse order.
function Add-Journal([string]$Id, [string]$Description, [string]$RevertCommand) {
    $o = [ordered]@{ Time = (Get-Date -Format 's'); Id = $Id; Description = $Description; RevertCommand = $RevertCommand; Reverted = $false }
    Add-Content -Path (Join-Path $script:Root 'journal.jsonl') -Value ($o | ConvertTo-Json -Compress) -Encoding utf8
    Write-Log "CHANGE [$Id] $Description"
}

function Backup-RegKey([string]$Key, [string]$Tag) {
    $f = Join-Path $script:Root ("backups\{0}-{1}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Tag)
    $null = & reg.exe export $Key $f /y 2>&1
    if ($LASTEXITCODE -ne 0) { Set-Content -Path "$f.absent" -Value "Key did not exist or could not be exported: $Key"; return "$f.absent" }
    return $f
}

# Run a script elevated from a non-admin session. Returns $true only if it really ran.
# (Start-Process -Verb RunAs errors are NON-terminating; a cancelled/timed-out UAC must be caught explicitly.)
function Invoke-Elevated([string]$ScriptPath, [string]$Arguments = '', [switch]$NoWait) {
    if (Test-Admin) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath $Arguments.Split(' ', [StringSplitOptions]::RemoveEmptyEntries); return $true }
    try {
        $p = Start-Process powershell.exe -Verb RunAs -PassThru -Wait:(-not $NoWait) -ErrorAction Stop `
             -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
        return $true
    } catch { Write-Warning "Elevation failed or UAC was cancelled/timed out: $($_.Exception.Message)"; return $false }
}

# Restore point that is VERIFIED (Checkpoint-Computer only warns when blocked by the 24 h limit).
function New-VerifiedRestorePoint([string]$Description) {
    if (-not (Test-Admin)) { Write-Warning 'Restore point needs admin'; return $false }
    $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $ok = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count -gt $before
    Write-Log ("RESTORE POINT '{0}': {1}" -f $Description, $(if ($ok) { 'created (verified)' } else { 'NOT created (24 h limit, System Protection off, or VSS busy)' }))
    return $ok
}

function Get-DriverSnapshot([string]$Tag) {
    $f = Join-Path $script:Root ("backups\pnputil-enum-{0}-{1}.txt" -f $Tag, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    & pnputil.exe /enum-drivers > $f
    return $f
}

# Display modes via user32 (correct DEVMODE layout; enumerating modes from PowerShell with [ref] structs is unreliable).
if (-not ('PCOptDisplay' -as [type])) {
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class PCOptDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern bool EnumDisplaySettingsA(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int ChangeDisplaySettingsExA(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);
  static DEVMODE New() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }
  public static int[] Current() { DEVMODE d = New(); if (!EnumDisplaySettingsA(null, -1, ref d)) return new int[]{0,0,0}; return new int[]{ d.dmPelsWidth, d.dmPelsHeight, d.dmDisplayFrequency }; }
  public static int MaxHz(int w, int h) { int best = 0; DEVMODE d = New(); for (int i = 0; EnumDisplaySettingsA(null, i, ref d); i++) { if (d.dmPelsWidth == w && d.dmPelsHeight == h && d.dmBitsPerPel == 32 && d.dmDisplayFrequency > best) best = d.dmDisplayFrequency; } return best; }
  public static string Modes(int w, int h) { var s = new SortedSet<int>(); DEVMODE d = New(); for (int i = 0; EnumDisplaySettingsA(null, i, ref d); i++) if (d.dmPelsWidth == w && d.dmPelsHeight == h) s.Add(d.dmDisplayFrequency); return string.Join(",", s); }
  public static int SetHz(int hz) { DEVMODE d = New(); EnumDisplaySettingsA(null, -1, ref d); d.dmDisplayFrequency = hz; d.dmFields = 0x400000;
    int t = ChangeDisplaySettingsExA(null, ref d, IntPtr.Zero, 0x2, IntPtr.Zero); if (t != 0) return 1000 + t;
    return ChangeDisplaySettingsExA(null, ref d, IntPtr.Zero, 0x1, IntPtr.Zero); }
}
'@
}
