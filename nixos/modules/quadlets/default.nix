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
in
{
  imports = [
    ./pg-dump.nix
    ./traefik.nix
    ./postgres.nix
    ./larapaper.nix
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

      # Rootless API socket so traefik can discover other pod containers.
      # The socket lives at /run/user/2000/podman/podman.sock once the user
      # session is live (linger ensures it always is).
      systemd.user.sockets.podman = {
        Unit.Description = "Podman API socket";
        Socket.ListenStream = "%t/podman/podman.sock";
        Install.WantedBy = [ "sockets.target" ];
      };
      systemd.user.services.podman = {
        Unit.Description = "Podman API service";
        Unit.Requires = [ "podman.socket" ];
        Service.Type = "exec";
        Service.ExecStart = "${pkgs.podman}/bin/podman system service";
        Service.Environment = "LOGGING=info";
      };

      # Shared quadlet networks. Name is pinned so the literal podman network
      # name matches what traefik.yml's `network: proxy` and the
      # `traefik.docker.network=proxy` label expect.
      virtualisation.quadlet.networks.proxy.networkConfig.name = "proxy";
      virtualisation.quadlet.networks.postgres.networkConfig.name = "postgres";
    };
  };

  # DNAT: redirect privileged 80/443 to the rootless traefik high ports.
  # Rootless processes can't bind ports below 1024; this is how the pod
  # user's traefik (8080/8443) receives public traffic.
  networking.firewall.allowedTCPPorts = [
    8080
    8443
  ];
  networking.firewall.extraCommands = ''
    iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || \
      iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080
    iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || \
      iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443
    iptables -t nat -C OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null || \
      iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080
    iptables -t nat -C OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443 2>/dev/null || \
      iptables -t nat -A OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443
  '';
  networking.firewall.extraStopCommands = ''
    iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080 || true
    iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443 || true
    iptables -t nat -D OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-ports 8080 || true
    iptables -t nat -D OUTPUT -o lo -p tcp --dport 443 -j REDIRECT --to-ports 8443 || true
  '';
}
