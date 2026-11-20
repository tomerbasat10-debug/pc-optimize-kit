# Install-Apps.ps1 - set up the user's regular apps from a folder of installers (e.g. "D:\New folder").
#   -Mode Plan     READ-ONLY: list every file, its signature, installer type, and the official winget package if one matches.
#   -Mode Install  install the approved items (-Only name1,name2 or all 'OK' items). Run ELEVATED (machine-wide installers).
# Policy: prefer winget (latest version, official source, hash-checked) > local installer with VALID Authenticode signature.
#         Archives (.rar/.zip/.7z) of commercial software, unsigned or invalid-signature files are NEVER auto-installed.
param([string]$Folder = 'D:\New folder', [ValidateSet('Plan','Install')][string]$Mode = 'Plan', [string[]]$Only, [switch]$LocalOnly)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace

# filename regex -> candidate winget id (verified at runtime with 'winget show --exact')
$Map = [ordered]@{
  'Discord'          = 'Discord.Discord';          'SpotifySetup'   = 'Spotify.Spotify';     'SteamSetup'   = 'Valve.Steam'
  '^Git-'            = 'Git.Git';                  'python-3\.13'   = 'Python.Python.3.13';  'python-3\.12' = 'Python.Python.3.12'
  'WhatsApp'         = '9NKSQGP7F2NH|msstore';     'EqualizerAPO'   = 'EqualizerAPO.EqualizerAPO'
  'directx_.*redist|dxwebsetup' = 'Microsoft.DirectX'; 'helium_'   = 'imput.Helium'
  'ChromeSetup|chrome' = 'Google.Chrome';          'Firefox'        = 'Mozilla.Firefox';     '7z\d+'        = '7zip.7zip'
  'vlc-'             = 'VideoLAN.VLC';             'OBS-Studio'     = 'OBSProject.OBSStudio'; 'VSCode'      = 'Microsoft.VisualStudioCode'
  'Notepad\+\+|npp\.' = 'Notepad++.Notepad++';     'EpicInstaller'  = 'EpicGames.EpicGamesLauncher'; 'Battle\.net' = 'Blizzard.BattleNet'
}

function Get-InstallerType([string]$f) {
    $ext = [IO.Path]::GetExtension($f).ToLower()
    if ($ext -eq '.msi') { return 'MSI' }
    if ($ext -ne '.exe') { return $null }
    $fs = [IO.File]::OpenRead($f); try { $n = [Math]::Min($fs.Length, 4MB); $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n) } finally { $fs.Close() }
    $s = [Text.Encoding]::ASCII.GetString($buf)
    if ($s -match 'Inno Setup') { 'Inno' } elseif ($s -match 'Nullsoft|NSIS') { 'NSIS' } elseif ($s -match 'Squirrel|SquirrelSetup') { 'Squirrel' }
    elseif ($s -match 'InstallShield') { 'InstallShield' } elseif ($s -match 'WixBundle|\.wixburn') { 'WixBurn' } else { 'Unknown' }
}
$Silent = @{ MSI = '/qn /norestart'; Inno = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'; NSIS = '/S'; Squirrel = '--silent'; WixBurn = '/quiet /norestart'; InstallShield = '/s /v"/qn"' }

function Test-Winget([string]$id) {
    if ($id -match '\|msstore') { $i = $id.Split('|')[0]; $o = winget show --id $i --exact --source msstore --disable-interactivity 2>$null; return [bool]($o -match '^Found') }
    $o = winget show --id $id --exact --source winget --disable-interactivity 2>$null; return [bool]($o -match '^Found')
}

$plan = foreach ($f in Get-ChildItem $Folder -File -ErrorAction Stop) {
    $item = [ordered]@{ Status = ''; File = $f.Name; MB = [math]::Round($f.Length/1MB,1); Method = ''; Detail = '' }
    $ext = $f.Extension.ToLower()
    if ($ext -in '.rar','.zip','.7z') { $item.Status = 'SKIP'; $item.Detail = 'Archive - not auto-installed. If this is paid software from an unofficial source, use the vendor installer instead.'; [pscustomobject]$item; continue }
    if ($ext -notin '.exe','.msi') { $item.Status = 'INFO'; $item.Detail = 'Not an installer (config/data file) - copy manually where needed'; [pscustomobject]$item; continue }
    $wid = $null; if (-not $LocalOnly) { foreach ($k in $Map.Keys) { if ($f.Name -match $k) { if (Test-Winget $Map[$k]) { $wid = $Map[$k] }; break } } }
    $sig = Get-AuthenticodeSignature $f.FullName
    $signer = if ($sig.SignerCertificate.Subject -match 'CN="?([^,"]+)') { $Matches[1] } else { "$($sig.SignerCertificate.Subject)" }
    if ($wid) { $item.Method = 'winget'; $item.Detail = "$wid (latest, official)"; $item.Status = 'OK' }
    elseif ($sig.Status -eq 'Valid') {
        $t = Get-InstallerType $f.FullName; $item.Method = "local:$t"; $item.Detail = "signed by $signer"; $item.Status = if ($Silent[$t]) { 'OK' } else { 'MANUAL' }
        $word = ($f.BaseName -replace '[-_\.\d]+',' ').Trim().Split(' ')[0]
        if ($word.Length -ge 4 -and $signer -notmatch [regex]::Escape($word)) { $item.Detail += " - publisher name differs from file name: confirm this is the expected vendor" }
    }
    else { $item.Method = 'none'; $item.Detail = "signature $($sig.Status) - not installed automatically"; $item.Status = 'BLOCKED' }
    [pscustomobject]$item
}
$plan | Format-Table -AutoSize -Wrap | Out-String -Width 220
$plan | ConvertTo-Json | Out-File (Join-Path $root 'apps-plan.json') -Encoding utf8
if ($Mode -eq 'Plan') { 'Plan only. Review, then:  Install-Apps.ps1 -Folder "<folder>" -Mode Install [-Only "Discord","Steam"]   (elevated)'; return }

$done = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in $plan | Where-Object Status -eq 'OK') {
    if ($Only -and -not ($Only | Where-Object { $p.File -match [regex]::Escape($_) })) { continue }
    if (-not $done.Add("$($p.Method)|$(if ($p.Method -eq 'winget') { $p.Detail } else { $p.File })")) { continue }
    $full = Join-Path $Folder $p.File
    if ($p.Method -eq 'winget') {
        $id = $p.Detail.Split(' ')[0]; $src = 'winget'; if ($id -match '\|msstore') { $id = $id.Split('|')[0]; $src = 'msstore' }
        winget install --id $id --exact --source $src --silent --disable-interactivity --accept-package-agreements --accept-source-agreements | Out-Null
        $rc = $LASTEXITCODE; if ($rc -eq -1978335189) { $rc = 0; $note = '(already installed)' } else { $note = '' }
        if ($rc -eq 0) { Add-Journal "APP-$id" "Installed $id via $src $note" "winget uninstall --id $id --exact --silent" } else { Write-Warning "$id failed (exit $rc)" }
    } else {
        $t = $p.Method.Split(':')[1]
        if ($t -eq 'MSI') { $proc = Start-Process msiexec.exe -ArgumentList "/i `"$full`" $($Silent.MSI)" -Wait -PassThru }
        else { $proc = Start-Process $full -ArgumentList $Silent[$t] -Wait -PassThru }
        if ($proc.ExitCode -in 0, 3010) { Add-Journal "APP-$($p.File)" "Installed local $($p.File) ($t, $($p.Detail))" 'Uninstall from Settings > Apps' } else { Write-Warning "$($p.File) exit $($proc.ExitCode)" }
    }
}
