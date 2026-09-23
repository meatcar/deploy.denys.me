#!/usr/bin/env bash
# Guard only inbound backend traffic, not replies to ZNC's outbound IRC sessions.
for tool in iptables ip6tables; do
  rule=(! -i lo -m addrtype --dst-type LOCAL -p tcp --dport @port@ -j DROP)
  "$tool" -w -t raw -C PREROUTING "${rule[@]}" 2>/dev/null ||
    "$tool" -w -t raw -I PREROUTING "${rule[@]}"
done
