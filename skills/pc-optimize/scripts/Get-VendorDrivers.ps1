# Get-VendorDrivers.ps1 - READ-ONLY. Finds the board vendor's latest drivers/BIOS for THIS motherboard and the support URLs.
# ASUS: queried through the official ASUS support API (direct dlcdnets.asus.com links + SHA-256 where published).
# Other vendors: prints the official support page to open (MSI / Gigabyte / ASRock pages are JS-heavy; let Claude read them).
param([int]$OsId = 52)   # ASUS osid 52 = Windows 11 64-bit
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
$model = $bb.Product.Trim(); $vendor = "$($bb.Manufacturer) $($bios.Manufacturer)"
"Board: $model  BIOS: $($bios.SMBIOSBIOSVersion)"
$isAsus = ($model -match '^(ROG|TUF|PRIME|ProArt|Pro WS|EX-)') -or ($vendor -match 'ASUS')
if ($isAsus) {
    $q = [uri]::EscapeDataString($model)
    try {
        $r = Invoke-RestMethod "https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=global&model=$q&osid=$OsId" -UserAgent 'pc-optimize-kit'
        $out = foreach ($cat in $r.Result.Obj) { $latest = $cat.Files | Select-Object -First 1; if ($latest) { [pscustomobject]@{ Category = $cat.Name; Title = $latest.Title; Version = $latest.Version; Date = $latest.ReleaseDate; Size = $latest.FileSize; SHA256 = $latest.sha256; Url = $latest.DownloadUrl.Global } } }
        $out | Format-List | Out-String -Width 250
        $out | ConvertTo-Json | Out-File (Join-Path $root 'vendor-drivers.json') -Encoding utf8
    } catch { "ASUS driver API failed: $($_.Exception.Message)" }
    try {
        $b = Invoke-RestMethod "https://www.asus.com/support/api/product.asmx/GetPDBIOS?website=global&model=$q" -UserAgent 'pc-optimize-kit'
        $lb = ($b.Result.Obj | Where-Object { $_.Name -match 'BIOS' } | Select-Object -First 1).Files | Select-Object -First 1
        if ($lb) { "Latest BIOS: $($lb.Version) ($($lb.ReleaseDate)) installed: $($bios.SMBIOSBIOSVersion) -> $(if ($lb.Version -eq $bios.SMBIOSBIOSVersion) {'UP TO DATE'} else {'UPDATE AVAILABLE - flash with EZ Flash from USB; read the release notes (ME firmware is one-way)'})" }
    } catch { "ASUS BIOS API failed (open the board's support page > BIOS & FIRMWARE): $($_.Exception.Message)" }
} else {
    $s = switch -Regex ($vendor) {
        'Micro-Star|MSI'  { "https://www.msi.com/search/$([uri]::EscapeDataString($model))" }
        'Gigabyte'        { "https://www.gigabyte.com/Search?kw=$([uri]::EscapeDataString($model))" }
        'ASRock'          { "https://www.asrock.com/support/index.asp?cat=Drivers" }
        default           { 'Board vendor support site (search the model name)' }
    }
    "Non-ASUS board ($vendor). Official support: $s"
}
"GPU drivers (official): NVIDIA https://www.nvidia.com/en-us/drivers/ | AMD https://www.amd.com/en/support/download/drivers.html | Intel Arc https://www.intel.com/content/www/us/en/download/785597/"
"Intel chipset INF (if no board package): https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html"
