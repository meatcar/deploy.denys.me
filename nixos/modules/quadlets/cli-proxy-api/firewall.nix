_: {
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 9443 ];
  # NOTE: Filter before rootless port forwarding and VPN-managed ACCEPT rules.
  networking.firewall.extraCommands = ''
    for tool in iptables ip6tables; do
      $tool-restore --noflush <<'RULES'
    *raw
    :cli-proxy-private - [0:0]
    -F cli-proxy-private
    -A cli-proxy-private -i wt0 -j RETURN
    -A cli-proxy-private -i lo -j RETURN
    -A cli-proxy-private -j DROP
    COMMIT
    RULES
      $tool -w -t raw -C PREROUTING -p tcp --dport 9443 -j cli-proxy-private 2>/dev/null || \
        $tool -w -t raw -I PREROUTING -p tcp --dport 9443 -j cli-proxy-private
      $tool -w -t nat -C PREROUTING -i wt0 -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 9443 2>/dev/null || \
        $tool -w -t nat -I PREROUTING 1 -i wt0 -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 9443
    done
  '';
}
