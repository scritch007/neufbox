#!/bin/sh
# Read-only health check of the UCG IGMP proxy (UniFi runs /usr/sbin/improxy, not igmpproxy).
echo ---PROC; ps -eo pid,args | grep -E 'improxy|igmpproxy' | grep -v grep
echo ---BIN; ls -l /usr/sbin/improxy /usr/sbin/improxy.bak /usr/sbin/igmpproxy 2>&1
echo ---CFG; grep -A 10 '"igmpProxy"' /data/udapi-config/udapi-net-cfg.json | head -n 11
echo ---RUNCFG; cat /run/improxy.conf 2>/dev/null
echo ---LOG; journalctl --no-pager --since "-1h" | grep -iE 'igmpProxy|improxy' | grep -vE 'Keep (running|stopped)' | tail -n 10
echo ---VIF; cat /proc/net/ip_mr_vif
echo ---MR; cat /proc/net/ip_mr_cache
