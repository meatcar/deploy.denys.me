#!/usr/bin/env bash
# These raw-table guards survive firewall stop and precede VPN-managed ACCEPTs.
for tool in iptables ip6tables; do
  "$tool-restore" --noflush <<'RULES'
*raw
:private-services - [0:0]
:private-administration - [0:0]
:private-storage - [0:0]
:private-discovery - [0:0]
-F private-services
-F private-administration
-F private-storage
-F private-discovery
-A private-services -i wt0 -j RETURN
-A private-services -i lo -j RETURN
-A private-services -j DROP
-A private-administration -i wt0 -j RETURN
-A private-administration -i tailscale0 -j RETURN
-A private-administration -i lo -j RETURN
-A private-administration -j DROP
-A private-storage -i wt0 -j RETURN
-A private-storage -i lo -j RETURN
@storageLANRules@
-A private-storage -j DROP
-A private-discovery -i lo -j RETURN
@discoveryLANRules@
-A private-discovery -j DROP
COMMIT
RULES
  guard() {
    "$tool" -w -t raw -C PREROUTING -m addrtype --dst-type LOCAL "$@" 2>/dev/null ||
      "$tool" -w -t raw -I PREROUTING -m addrtype --dst-type LOCAL "$@"
  }
  guard -p tcp -m multiport --dports @privateTCPPorts@ -j private-services
  guard -p tcp --dport 22 -j private-administration
  guard -p udp --dport 60000:61000 -j private-administration
  guard -p tcp -m multiport --dports 139,445 -j private-storage
  guard -p tcp -m multiport --dports 3702,5357 -j private-discovery
  guard -p udp -m multiport --dports 137,138,3702 -j private-discovery
  "$tool" -w -t nat -C PREROUTING -i wt0 -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 9443 2>/dev/null ||
    "$tool" -w -t nat -I PREROUTING -i wt0 -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 9443
done
