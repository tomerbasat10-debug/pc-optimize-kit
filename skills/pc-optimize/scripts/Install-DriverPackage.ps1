# Install-DriverPackage.ps1 - install ONE official driver package safely. Run ELEVATED.
# Always: export all current third-party drivers once (backup), snapshot driver store before/after (for Revert-All), journal.
#   -Kind Inf      : folder/zip containing .inf files -> Windows pnputil /add-driver /install (never a bundled pnputil copy)
#   -Kind Nvidia   : NVIDIA driver .exe -> extract with tar, install ONLY the INF matching this GPU's hardware ID via pnputil.
#                    (Do NOT use NVIDIA setup.exe -s -clean: it removes the old driver first and can fail with 0x80070005,
#                     leaving the GPU driverless. NVIDIA Control Panel then comes from the Microsoft Store: 9NF8H0H7WMLT.)
#   -Kind Setup    : vendor installer with silent args (-SetupArgs), e.g. Intel SetupChipset.exe "-s -norestart", SetupME.exe "-s"
param([Parameter(Mandatory)][string]$Path, [ValidateSet('Inf','Nvidia','Setup')][string]$Kind = 'Inf', [string]$SetupArgs = '', [string]$Name)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
if (-not (Test-Admin)) { throw 'Run elevated' }
if (-not $Name) { $Name = [IO.Path]::GetFileNameWithoutExtension($Path) }

$bk = Get-ChildItem (Join-Path $root 'backups') -Directory -Filter 'drivers-before-*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bk) { $bk = Join-Path $root ("backups\drivers-before-" + (Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Force $bk | Out-Null; & pnputil.exe /export-driver * $bk | Select-Object -Last 2; Write-Log "DRIVER BACKUP: all third-party drivers exported to $bk" }
$before = Get-DriverSnapshot 'before'

$work = Join-Path $root ("downloads\pkg-" + ($Name -replace '[^\w\.-]','_'))
if ((Test-Path $Path -PathType Leaf) -and $Path -match '\.zip$') { Expand-Archive $Path -DestinationPath $work -Force; $src = $work } else { $src = $Path }

switch ($Kind) {
  'Inf' {
    $sig = Get-ChildItem $src -Recurse -Filter *.cat | Select-Object -First 1 | ForEach-Object { (Get-AuthenticodeSignature $_.FullName).Status }
    "Catalog signature: $sig"
    & "$env:windir\System32\pnputil.exe" /add-driver (Join-Path $src '*.inf') /subdirs /install; $rc = $LASTEXITCODE
  }
  'Nvidia' {
    $s = Get-AuthenticodeSignature $Path; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'NVIDIA') { throw "NVIDIA package signature invalid: $($s.Status)" }
    New-Item -ItemType Directory -Force $work | Out-Null; & tar -xf $Path -C $work
    $gpu = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI\VEN_10DE*' -and $_.Class -eq 'Display' } | Select-Object -First 1
    if (-not $gpu) { $gpu = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI\VEN_10DE&DEV_*' } | Where-Object FriendlyName -notmatch 'Audio' | Select-Object -First 1 }
    $hw = ($gpu.InstanceId -replace '&REV_.*','')   # PCI\VEN_10DE&DEV_xxxx&SUBSYS_yyyyyyyy
    $inf = Select-String -Path (Join-Path $work 'Display.Driver\*.inf') -Pattern ([regex]::Escape($hw)) -List | Select-Object -First 1
    if (-not $inf) { $dev = ($hw -replace '&SUBSYS.*',''); $inf = Select-String -Path (Join-Path $work 'Display.Driver\*.inf') -Pattern ([regex]::Escape($dev) + '(?!&SUBSYS)') -List | Select-Object -First 1 }
    if (-not $inf) { throw "No INF in package matches $hw" }
    "Matched $($inf.Filename) for $hw"
    & "$env:windir\System32\pnputil.exe" /add-driver $inf.Path /install; $rc = $LASTEXITCODE
    if (-not (Get-AppxPackage -AllUsers *NVIDIACorp.NVIDIAControlPanel* -ErrorAction SilentlyContinue)) { 'NVIDIA Control Panel not installed: Microsoft Store product 9NF8H0H7WMLT (Windows usually adds it after a reboot).' }
  }
  'Setup' {
    $s = Get-AuthenticodeSignature $Path; "Installer signature: $($s.Status) $($s.SignerCertificate.Subject)"
    if ($s.Status -ne 'Valid') { throw 'Installer is not validly signed - aborting' }
    $p = Start-Process $Path -ArgumentList $SetupArgs -Wait -PassThru; $rc = $p.ExitCode
  }
}
$after = Get-DriverSnapshot 'after'
"exit code: $rc  (0 = OK, 3010 = OK, reboot needed)"
Add-Journal "DRV-$Name" "Driver package $Name ($Kind) exit $rc" "& `"$PSScriptRoot\Revert-Driver.ps1`" -Before `"$before`" -After `"$after`" -Backup `"$bk`""
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, ConfigManagerErrorCode | Format-Table -AutoSize

