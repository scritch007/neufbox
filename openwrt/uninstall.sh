#!/bin/sh
# Undoes install.sh (restores the original igmpproxy/uhttpd configs).
set -e
[ -f /etc/config/igmpproxy.orig ] && cp /etc/config/igmpproxy.orig /etc/config/igmpproxy
/etc/init.d/igmpproxy disable || true
/etc/init.d/igmpproxy stop || true

idx=$(uci show firewall | sed -n "s/^firewall\.@rule\[\([0-9]*\)\]\.name='Allow-IPTV-Multicast'$/\1/p")
[ -n "$idx" ] && uci delete "firewall.@rule[$idx]" && uci commit firewall && /etc/init.d/firewall restart

[ -f /etc/config/uhttpd.orig ] && cp /etc/config/uhttpd.orig /etc/config/uhttpd && /etc/init.d/uhttpd restart
rm -rf /www/api

idx=$(uci show dhcp | sed -n "s/^dhcp\.@domain\[\([0-9]*\)\]\.name='neufbox'$/\1/p")
[ -n "$idx" ] && uci delete "dhcp.@domain[$idx]" && uci commit dhcp && /etc/init.d/dnsmasq restart
echo "removed"
