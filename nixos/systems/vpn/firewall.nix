_: {
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 51821 ];
    interfaces.wt0.allowedTCPPorts = [ 443 ];
    # NOTE: Raw ingress filtering precedes NetBird's dynamically managed ACCEPT rules.
    extraCommands = ''
      for tool in iptables ip6tables; do
        $tool-restore --noflush <<'RULES'
      *raw
      :bao-private - [0:0]
      -F bao-private
      -A bao-private -i wt0 -j RETURN
      -A bao-private -i lo -j RETURN
      -A bao-private -j DROP
      COMMIT
      RULES
        $tool -t raw -C PREROUTING -p tcp -m multiport --dports 443,8200,8201 -j bao-private 2>/dev/null || \
          $tool -t raw -I PREROUTING -p tcp -m multiport --dports 443,8200,8201 -j bao-private
      done
    '';
  };
}
