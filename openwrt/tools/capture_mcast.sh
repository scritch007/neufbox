#!/bin/sh
# Captures IGMP from the decoder and multicast arriving from the UCG for 25 s
tcpdump -lni br-lan -v -c 40 igmp > /tmp/igmp_lan.txt 2>&1 &
p1=$!
tcpdump -lni br-wan-bridge -v -c 20 'ip multicast and not port 1900 and not port 5353' > /tmp/mc_wan.txt 2>&1 &
p2=$!
tcpdump -lni br-wan-bridge -v -c 40 igmp > /tmp/igmp_wan.txt 2>&1 &
p3=$!
sleep 25
kill $p1 $p2 $p3 2>/dev/null
echo ---IGMP_LAN; grep -vE '^(tcpdump|listening)' /tmp/igmp_lan.txt | head -n 30
echo ---IGMP_WAN; grep -vE '^(tcpdump|listening)' /tmp/igmp_wan.txt | head -n 30
echo ---MCAST_WAN; grep -vE '^(tcpdump|listening)' /tmp/mc_wan.txt | head -n 20
echo ---MR; cat /proc/net/ip_mr_cache
