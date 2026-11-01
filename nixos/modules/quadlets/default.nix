{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  persistPath = config.mine.persistPath;
  # NOTE: Cloudflare proxies public browser traffic.
  # see https://www.cloudflare.com/ips/
  cloudflareIpv4 = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
  ];
  proxySourceRules = map (cidr: {
    inherit cidr;
    ports = "8080,8443";
  }) cloudflareIpv4;
  proxyAllowRules = lib.concatMapStringsSep "\n" (rule: ''
    iptables -w -C nixos-fw -s ${rule.cidr} -p tcp -m multiport --dports ${rule.ports} -j nixos-fw-accept 2>/dev/null || \
      iptables -w -I nixos-fw 1 -s ${rule.cidr} -p tcp -m multiport --dports ${rule.ports} -j nixos-fw-accept
  '') proxySourceRules;
  proxyRemoveRules = lib.concatMapStringsSep "\n" (rule: ''
    iptables -w -D nixos-fw -s ${rule.cidr} -p tcp -m multiport --dports ${rule.ports} -j nixos-fw-accept 2>/dev/null || true
  '') proxySourceRules;
in
{
  imports = [
    ./pg-dump.nix
    ./mysql-dump.nix
    ./traefik.nix
    ./postgres.nix
    ./larapaper
    ./invoiceninja
    ./cli-proxy-api
    ./silverbullet
  ];

  # NOTE: uid/gid pinned for stable named-volume ownership.
  users.groups.pod.gid = 2000;
  users.users.pod = {
    isNormalUser = true;
    uid = 2000;
    group = "pod";
    home = "${persistPath}/pod";
    createHome = true;
    autoSubUidGidRange = true;
  };

  system.activationScripts.pod-linger = {
    text = "${pkgs.systemd}/bin/loginctl enable-linger pod";
    deps = [
      "users"
      "groups"
    ];
  };

  # NOTE: sd-switch runs `systemctl --user`; without this ordering it races user@2000 on first boot and hangs.
  systemd.services."home-manager-pod" = {
    after = lib.mkAfter [ "user@${toString config.users.users.pod.uid}.service" ];
    wants = [ "user@${toString config.users.users.pod.uid}.service" ];
  };

  # NOTE: No dockerCompat/dockerSocket: Docker runs on this host for transit-dashboard.
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.pod = {
      imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "26.05";

      # NOTE: Do not expose the podman API socket: an internet-facing process with a container-runtime API is a root escalation path.

      # NOTE: Names pinned to match the service URLs in traefik dynamic config.
      virtualisation.quadlet.networks.proxy.networkConfig = {
        name = "proxy";
        subnets = [ "10.89.1.0/24" ];
      };
      virtualisation.quadlet.networks.postgres.networkConfig = {
        name = "postgres";
        subnets = [ "10.89.0.0/24" ];
      };
    };
  };

  # NOTE: Filter Cloudflare sources in nixos-fw, before rootlessport hides the peer IP from traefik.
  networking.firewall.extraCommands = ''
    ${proxyAllowRules}
    iptables -w -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || true
    iptables -w -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || true
    iptables -w -t nat -C PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || \
      iptables -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 80 -j REDIRECT --to-ports 8080
    iptables -w -t nat -C PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || \
      iptables -w -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 8443
    iptables -w -t nat -C OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || \
      iptables -w -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080
    iptables -w -t nat -C OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || \
      iptables -w -t nat -A OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443
  '';
  networking.firewall.extraStopCommands = ''
    ${proxyRemoveRules}
    iptables -w -t nat -D PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || true
    iptables -w -t nat -D PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || true
    iptables -w -t nat -D OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || true
    iptables -w -t nat -D OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || true
  '';
}
