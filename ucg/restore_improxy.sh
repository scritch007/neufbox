#!/bin/sh
# Repairs UniFi's built-in IGMP proxy after the 2026-09-26 manual igmpproxy attempt:
# /usr/sbin/improxy had been renamed to improxy.bak, so udapi-server failed with
# "execve failed: No such file or directory". Toggle IGMP Proxy off/on in the UI afterwards.
set -e
if [ ! -x /usr/sbin/improxy ] && [ -f /usr/sbin/improxy.bak ]; then
  cp -p /usr/sbin/improxy.bak /usr/sbin/improxy
fi
# The Debian igmpproxy package is not part of the firmware and conflicts with improxy
if dpkg -l igmpproxy 2>/dev/null | grep -qE '^(ii|rc)'; then
  systemctl disable --now igmpproxy 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get purge -y igmpproxy
fi
ls -l /usr/sbin/improxy
