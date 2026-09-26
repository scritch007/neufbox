#!/bin/sh
# Emulates the SFR neufbox API (/api/1.0/?method=...) expected by the SFR TV decoder.
# Response formats taken from fl0w's TV.tgz on lafibre.info (UCG Ultra + TV thread).
dir=/www/api/1.0
log=/tmp/neufbox_api.log
[ -f "$log" ] && [ "$(wc -c < "$log")" -gt 65536 ] && : > "$log"
echo "$(date '+%F %T') $REMOTE_ADDR $QUERY_STRING" >> "$log"

method=$(echo "$QUERY_STRING" | sed -n 's/.*method=\([A-Za-z.]*\).*/\1/p')
printf 'Content-Type: application/xml; charset=utf-8\r\n\r\n'

# Real XML dumped from the SFR box takes precedence
if [ -n "$method" ] && [ -f "$dir/$method.xml" ]; then
  cat "$dir/$method.xml"
  exit 0
fi

echo '<?xml version="1.0" ?>'
up=$(cut -d. -f1 /proc/uptime)
case "$method" in
  system.getInfo)
    mac=$(cat /sys/class/net/br-lan/address)
    now=$(date +%Y%m%d%H%M)
    cat <<EOF
<rsp stat="ok" version="1.0">
<system product_id="NB6VAC-FXC-r0" serial_number="NB6VAC000000000" mac_addr="$mac" net_mode="router" net_infra="ftth" uptime="$up" version_mainfirmware="NB6VAC-MAIN-R4.0.45d" version_rescuefirmware="NB6VAC-MAIN-R4.0.44k" version_bootloader="NB6VAC-BOOTLOADER-R4.0.8" version_dsldriver="NB6VAC-XDSL-A2pv6F039p" current_datetime="$now" refclient="" idur="" alimvoltage="12251" temperature="47055"/>
</rsp>
EOF
    ;;
  wan.getInfo)
    # Public IP is fetched once and cached; the decoder polls every few seconds
    ipf=/tmp/neufbox_wanip
    [ -s "$ipf" ] || uclient-fetch -q -T 5 -O - https://api.ipify.org 2>/dev/null | grep -oE '^[0-9.]+$' > "$ipf"
    cat <<EOF
<rsp stat="ok" version="1.0">
<wan status="up" uptime="$up" ip_addr="$(cat "$ipf")" infra="ftth" mode="ftth/routed" infra6="" status6="down" uptime6="" ipv6_addr=""/>
</rsp>
EOF
    ;;
  ftth.getInfo)
    printf '<rsp stat="ok" version="1.0">\n<ftth status="up" wanfibre="in"/>\n</rsp>\n'
    ;;
  lan.getHostsList)
    echo '<rsp stat="ok" version="1.0">'
    while read -r _ mac ip name _; do
      [ "$ip" = "$REMOTE_ADDR" ] && type=stb || type=pc
      echo "<host type=\"$type\" name=\"$name\" ip=\"$ip\" mac=\"$mac\" iface=\"lan1\" probe=\"60\" alive=\"$up\" status=\"online\"/>"
    done < /tmp/dhcp.leases
    echo '</rsp>'
    ;;
  tv.getInfo)
    printf '<rsp stat="ok" version="1.0">\n<tv infra="ftth/routed" lanchain="" netchain=""/>\n<igmps> </igmps>\n</rsp>\n'
    ;;
  usb.getInfo)
    echo '<rsp stat="ok" version="1.0"> </rsp>'
    ;;
  *)
    printf '<rsp stat="fail" version="1.0">\n<err code="112" msg="Method not found"/>\n</rsp>\n'
    ;;
esac
