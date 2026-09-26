#!/bin/sh
# Shows what the decoder is doing: box API calls, multicast routes, outside connections.
stb=${1:-192.168.1.187}
echo ---APILOG
tail -n 15 /tmp/neufbox_api.log
echo ---MR
cat /proc/net/ip_mr_cache
echo ---EXT
grep "src=$stb" /proc/net/nf_conntrack | grep -v 'dst=192.168.1.1 ' \
  | sed -E 's/.* (tcp|udp) +[0-9]+ [0-9]+ ([A-Z_]+ )?src=[0-9.]+ dst=([0-9.]+) sport=[0-9]+ dport=([0-9]+).*/\1 \3:\4 \2/' \
  | sort | uniq -c | sort -rn | head -n 25
