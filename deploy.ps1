# Pushes neufbox/openwrt to the OpenWrt router and runs install.sh.
# Usage: .\deploy.ps1 [-Router root@192.168.100.88]
param([string]$Router = "root@192.168.100.88")
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot "openwrt"

ssh -o BatchMode=yes $Router "rm -rf /tmp/neufbox && mkdir -p /tmp/neufbox/www/api/1.0 /tmp/neufbox/etc/config"

# Piping through tr strips the CRLF that PowerShell adds
$files = @(
    "www/api/1.0/index.sh",
    "etc/config/igmpproxy",
    "install.sh",
    "uninstall.sh",
    "tools/check_decoder.sh",
    "tools/capture_mcast.sh"
)
foreach ($f in $files) {
    $dest = "/tmp/neufbox/$f"
    Get-Content (Join-Path $root $f) | ssh -o BatchMode=yes $Router "mkdir -p `$(dirname $dest) && tr -d '\r' > $dest && chmod 755 $dest"
}

ssh -o BatchMode=yes $Router "mkdir -p /root/neufbox && cp -r /tmp/neufbox/. /root/neufbox/ && sh /root/neufbox/install.sh"
