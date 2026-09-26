#!/bin/sh
# Sets up the SFR TV decoder behind OpenWrt 25.x (apk) sitting behind the UCG.
# Expects this folder's www/ and etc/ copied to /tmp/neufbox first (see ../deploy.ps1).
# Idempotent: safe to re-run.
set -e
src=/tmp/neufbox

apk update >/dev/null
apk add igmpproxy tcpdump

# IGMP proxy wan -> lan
[ -f /etc/config/igmpproxy.orig ] || cp /etc/config/igmpproxy /etc/config/igmpproxy.orig
cp "$src/etc/config/igmpproxy" /etc/config/igmpproxy
/etc/init.d/igmpproxy enable
/etc/init.d/igmpproxy restart

# Let the TV multicast stream through wan -> lan
if ! uci show firewall | grep -q "name='Allow-IPTV-Multicast'"; then
  uci add firewall rule >/dev/null
  uci set firewall.@rule[-1].name='Allow-IPTV-Multicast'
  uci set firewall.@rule[-1].src='wan'
  uci set firewall.@rule[-1].dest='lan'
  uci set firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].dest_ip='224.0.0.0/4'
  uci set firewall.@rule[-1].target='ACCEPT'
  uci commit firewall
  /etc/init.d/firewall restart
fi

# Box API emulation served by uhttpd at http://192.168.1.1/api/1.0/
mkdir -p /www/api/1.0
cp "$src/www/api/1.0/index.sh" /www/api/1.0/index.sh
chmod 755 /www/api/1.0/index.sh
[ -f /etc/config/uhttpd.orig ] || cp /etc/config/uhttpd /etc/config/uhttpd.orig
uci show uhttpd.main.interpreter 2>/dev/null | grep -q "\.sh=/bin/sh" || uci add_list uhttpd.main.interpreter='.sh=/bin/sh'
if ! uci show uhttpd.main.index_page 2>/dev/null | grep -q index.sh; then
  uci show uhttpd.main.index_page >/dev/null 2>&1 || uci add_list uhttpd.main.index_page='index.html'
  uci add_list uhttpd.main.index_page='index.sh'
fi
uci commit uhttpd
/etc/init.d/uhttpd restart

# The decoder also looks up "neufbox"
if ! uci show dhcp | grep -q "name='neufbox'"; then
  uci add dhcp domain >/dev/null
  uci set dhcp.@domain[-1].name='neufbox'
  uci set dhcp.@domain[-1].ip='192.168.1.1'
  uci commit dhcp
  /etc/init.d/dnsmasq restart
fi

echo "--- self test"
uclient-fetch -q -O - 'http://192.168.1.1/api/1.0/?method=system.getInfo'
echo "OK"
