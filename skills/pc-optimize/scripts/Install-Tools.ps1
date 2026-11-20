# Install-Tools.ps1 - install measurement tools from OFFICIAL sources with verification. Run ELEVATED (PawnIO driver + winget machine installs).
#   LHM        LibreHardwareMonitor (GitHub release, sha256 must match GitHub asset digest) + PawnIO driver (winget, hash-verified)
#   PresentMon Intel PresentMon CLI (GitHub release, Authenticode must be Intel)
#   NPI        NVIDIA Profile Inspector (GitHub release, sha256 digest) - only useful on NVIDIA GPUs
#   Bench      Cinebench R23 + OCCT Personal (winget)
# Note: HWiNFO's site blocks scripted downloads (Cloudflare) and LatencyMon cannot be automated - use LHM + Measure-Dpc.ps1 instead.
param([string[]]$Components = @('LHM','PresentMon','NPI','Bench'))
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$tools = Join-Path $root 'tools'; $dl = Join-Path $root 'downloads'
$ProgressPreference = 'SilentlyContinue'
$UA = 'pc-optimize-kit'

function Get-GitHubAsset([string]$Repo, [string]$NamePattern) {
    $r = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -UserAgent $UA
    $a = $r.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
    if (-not $a) { throw "No asset matching $NamePattern in $Repo $($r.tag_name)" }
    $dir = Join-Path $dl ($Repo -replace '/','_'); New-Item -ItemType Directory -Force $dir | Out-Null
    $f = Join-Path $dir $a.name
    Invoke-WebRequest $a.browser_download_url -OutFile $f -UseBasicParsing -UserAgent $UA
    $h = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
    $ok = if ($a.digest) { $a.digest -eq "sha256:$h" } else { $null }
    [pscustomobject]@{ File = $f; Tag = $r.tag_name; Sha256 = $h; DigestMatch = $ok }
}

if ($Components -contains 'LHM') {
    $x = Get-GitHubAsset 'LibreHardwareMonitor/LibreHardwareMonitor' '^LibreHardwareMonitor\.zip$'
    if ($x.DigestMatch -ne $true) { Write-Warning "LHM digest check failed/unavailable ($($x.DigestMatch)) - not installing"; }
    else {
        Expand-Archive $x.File -DestinationPath (Join-Path $tools 'LibreHardwareMonitor') -Force
        Add-Journal 'TOOL-LHM' "LibreHardwareMonitor $($x.Tag) portable (sha256 verified vs GitHub)" "Remove-Item '$tools\LibreHardwareMonitor' -Recurse -Force"
        winget install --id namazso.PawnIO --exact --source winget --silent --disable-interactivity --accept-package-agreements | Out-Null
        if ($LASTEXITCODE -eq 0 -or (Get-Service PawnIO -ErrorAction SilentlyContinue)) { Add-Journal 'TOOL-PAWNIO' 'PawnIO driver (winget, hash verified) for CPU sensors' 'winget uninstall --id namazso.PawnIO --exact --silent' } else { Write-Warning "PawnIO install exit $LASTEXITCODE" }
    }
}
if ($Components -contains 'PresentMon') {
    $x = Get-GitHubAsset 'GameTechDev/PresentMon' '^PresentMon-[\d\.]+-x64\.exe$'
    $sig = Get-AuthenticodeSignature $x.File
    if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Intel Corporation') {
        Copy-Item $x.File (Join-Path $tools 'PresentMon.exe') -Force
        Add-Journal 'TOOL-PRESENTMON' "PresentMon $($x.Tag) (Intel-signed)" "Remove-Item '$tools\PresentMon.exe' -Force"
    } else { Write-Warning "PresentMon signature not valid Intel: $($sig.Status) $($sig.SignerCertificate.Subject)" }
}
if ($Components -contains 'NPI' -and (Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA')) {
    $x = Get-GitHubAsset 'Orbmu2k/nvidiaProfileInspector' '^nvidiaProfileInspector\.zip$'
    if ($x.DigestMatch -eq $true) { Expand-Archive $x.File -DestinationPath (Join-Path $tools 'NPI') -Force; Add-Journal 'TOOL-NPI' "NVIDIA Profile Inspector $($x.Tag) (sha256 verified)" "Remove-Item '$tools\NPI' -Recurse -Force" }
    else { Write-Warning 'NPI digest check failed - not installing' }
}
if ($Components -contains 'Bench') {
    foreach ($id in 'Maxon.CinebenchR23','OCBase.OCCT.Personal') {
        winget install --id $id --exact --source winget --silent --disable-interactivity --accept-package-agreements | Out-Null
        if ($LASTEXITCODE -eq 0) { Add-Journal "TOOL-$id" "$id via winget" "winget uninstall --id $id --exact --silent" } else { Write-Warning "$id winget exit $LASTEXITCODE (stale manifest hash? download from the vendor site and verify the signature)" }
    }
}
Get-ChildItem $tools | Select-Object Name
