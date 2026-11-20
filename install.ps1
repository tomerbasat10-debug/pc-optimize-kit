# install.ps1 - install the pc-optimize skill for Claude Code on this PC (no admin needed).
# Usage (from the repo folder):  powershell -ExecutionPolicy Bypass -File .\install.ps1
$src = Join-Path $PSScriptRoot 'skills\pc-optimize'
$dst = Join-Path $env:USERPROFILE '.claude\skills\pc-optimize'
if (-not (Test-Path $src)) { throw "Skill folder not found: $src" }
New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $src $dst -Recurse -Force
Get-ChildItem $dst -Recurse -Filter *.ps1 | Unblock-File
"Installed to $dst"
"Open Claude Code and say: optimize this PC   (or type /pc-optimize)"
