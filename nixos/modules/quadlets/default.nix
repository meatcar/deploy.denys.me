# Rootless Podman Quadlets platform module.
# Wires up the `pod` service user, podman, home-manager/quadlet-nix, shared
# networks, and the 80/443 → 8080/8443 DNAT so rootless traefik is reachable.
# All quadlet service modules live alongside this file and are imported here.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  persistPath = config.mine.persistPath;
  # https://www.cloudflare.com/ips/ — public browser traffic is proxied.
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
  # SNS HTTPS delivery currently originates from this AWS-owned, non-EC2
  # ca-central-1 service prefix. The dedicated router accepts only the signed
  # webhook path and validates the configured TopicArn inside Invoice Ninja.
  awsSnsIpv4 = [ "52.94.80.0/20" ];
  proxySourceRules =
    map (cidr: {
      inherit cidr;
      ports = "8080,8443";
    }) cloudflareIpv4
    ++ map (cidr: {
      inherit cidr;
      ports = "8443";
    }) awsSnsIpv4;
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
    ./larapaper.nix
    ./invoiceninja.nix
  ];

  # Dedicated, unprivileged service user that owns the rootless podman session.
  # uid/gid are pinned so named-volume ownership is stable across rebuilds.
  users.groups.pod.gid = 2000;
  users.users.pod = {
    isNormalUser = true;
    uid = 2000;
    group = "pod";
    home = "${persistPath}/pod";
    createHome = true;
    # autoSubUidGidRange allocates 65536 subordinate ids for userns
    autoSubUidGidRange = true;
  };

  # Enable linger so the pod user's systemd session (and containers) survive
  # without an interactive login.
  system.activationScripts.pod-linger = {
    text = "${pkgs.systemd}/bin/loginctl enable-linger pod";
    deps = [
      "users"
      "groups"
    ];
  };

  # home-manager-pod runs sd-switch which calls `systemctl --user` against the
  # pod session. Without this ordering it races user@2000.service on first boot
  # and can hang if the session isn't ready yet.
  systemd.services."home-manager-pod" = {
    after = lib.mkAfter [ "user@${toString config.users.users.pod.uid}.service" ];
    wants = [ "user@${toString config.users.users.pod.uid}.service" ];
  };

  # Rootless podman. dockerCompat/dockerSocket intentionally disabled —
  # Docker is still running for transit-dashboard on the same host.
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
  };

  # Wire home-manager for the pod user so quadlet-nix's HM module can declare
  # rootless container/network/volume units in ~pod/.config/containers/systemd/.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.pod = {
      imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "26.05";

      # The rootless podman API socket used to be exposed here so traefik's
      # docker provider could discover containers. Traefik now routes from a
      # static file provider (see traefik.nix), and nothing else consumed the
      # socket, so it is gone: an internet-facing process holding a
      # container-runtime API was the single largest escalation path on this
      # host.

      # Shared quadlet networks. Name is pinned so the literal podman network
      # name matches the `proxy` service URLs in traefik's dynamic config.
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

  # DNAT: redirect privileged 80/443 to the rootless Traefik high ports.
  # The ports are not globally opened: source-specific rules admit Cloudflare
  # and the AWS SNS delivery prefix before the standard NixOS reject rule. This
  # preserves the peer IP until policy enforcement even though rootlessport
  # hides it from Traefik.
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
