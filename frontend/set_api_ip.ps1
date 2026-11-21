# Point the app at this PC's current LAN address.
#
#   cd frontend
#   .\set_api_ip.bat            # detect this PC's Wi-Fi/Ethernet IP and write it into env/dev.json
#   .\set_api_ip.bat 10.0.0.5   # or set one by hand
#
# Why: the phone and the browser reach the backend over the network, so
# env/dev.json holds this PC's IP. Wi-Fi hands out a new one now and then
# (it changed from 192.168.1.2 to 192.168.100.72 on 17 Nov), and then every
# request fails with "connection timeout". Run this, then restart the app.
param([string]$Ip)

$ErrorActionPreference = 'Stop'
$devJson = Join-Path $PSScriptRoot 'env\dev.json'
if (-not (Test-Path $devJson)) { throw "Not found: $devJson" }

if (-not $Ip) {
  # a real LAN address: skip loopback, link-local and virtual adapters
  $candidates = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|VirtualBox|VMware|Hyper-V|WSL' }
  # prefer Wi-Fi, then Ethernet, then whatever is left
  $pick = $candidates | Sort-Object @{ Expression = {
      switch -Regex ($_.InterfaceAlias) { 'Wi-?Fi' { 0 } 'Ethernet' { 1 } default { 2 } } } } |
    Select-Object -First 1
  if (-not $pick) { throw "No network address found. Are you connected to Wi-Fi?" }
  $Ip = $pick.IPAddress
  "Found this PC at $Ip ($($pick.InterfaceAlias))"
}

$url = "http://${Ip}:8000/api/v1"
$text = Get-Content $devJson -Raw
$updated = [regex]::Replace($text, '"API_BASE_URL"\s*:\s*"[^"]*"', '"API_BASE_URL": "' + $url + '"')
if ($updated -eq $text) {
  "env/dev.json already points at $url"
} else {
  Set-Content -Path $devJson -Value $updated -Encoding utf8 -NoNewline
  "env/dev.json now points at $url"
}
""
"Check the backend answers there:  curl http://${Ip}:8000/health"
"Then FULLY RESTART the app (press q, then flutter run ...). A rebuilt APK is"
"needed too if you test on the phone - the address is baked into the build."
