{
  config,
  lib,
  pkgs,
  ...
}:
let
  netbird = config.services.netbird.clients.default;
in
{
  imports = [
    ../vpn/common.nix
    ../vpn/firewall.nix
  ];
  networking.hostName = "bao";
  services.netbird = {
    enable = true;
    ui.enable = false;
    clients.default = {
      port = lib.mkForce 51821;
      openInternalFirewall = false;
      config = {
        ManagementURL = {
          Scheme = "https";
          Host = "api.netbird.io:443";
        };
        ServerSSHAllowed = false;
        DisableServerRoutes = true;
        DisableClientRoutes = true;
      };
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@denys.me";
    certs."bao.vpn.denys.me" = {
      domain = "bao.vpn.denys.me";
      dnsProvider = "cloudflare";
      environmentFile = "/etc/vpn/acme.env";
      group = "openbao";
      reloadServices = [ "openbao.service" ];
    };
  };
  users.groups.openbao = { };
  users.users.openbao = {
    isSystemUser = true;
    group = "openbao";
  };
  services.openbao = {
    enable = true;
    settings = {
      ui = true;
      disable_mlock = true;
      plugin_directory = "${import ./aws-auth-plugin.nix { inherit pkgs; }}";
      api_addr = "https://bao.vpn.denys.me";
      cluster_addr = "https://127.0.0.1:8201";
      storage.raft = {
        path = "/var/lib/openbao/raft";
        node_id = "bao";
      };
      seal.awskms = {
        region = "ca-central-1";
        kms_key_id = "alias/openbao-vpn";
      };
      audit = [
        {
          type = "file";
          path = "file";
          options.file_path = "/var/lib/openbao/audit.log";
        }
      ];
      listener.private = {
        type = "tcp";
        address = ''{{ GetInterfaceIP "wt0" }}:443'';
        cluster_address = "127.0.0.1:8201";
        tls_cert_file = "/var/lib/acme/bao.vpn.denys.me/fullchain.pem";
        tls_key_file = "/var/lib/acme/bao.vpn.denys.me/key.pem";
        tls_min_version = "tls12";
      };
    };
  };
  systemd.services.openbao = {
    after = [
      "${netbird.service.name}.service"
      "acme-bao.vpn.denys.me.service"
    ];
    wants = [ "${netbird.service.name}.service" ];
    unitConfig.ConditionPathExists = "/etc/vpn/openbao.env";
    startLimitIntervalSec = 0;
    restartIfChanged = lib.mkForce true;
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = lib.mkForce [ "CAP_NET_BIND_SERVICE" ];
      # NOTE: Binding host-network privileged ports requires the host user namespace.
      PrivateUsers = lib.mkForce false;
      EnvironmentFile = "/etc/vpn/openbao.env";
      RestrictAddressFamilies = [ "AF_NETLINK" ];
      RestartSec = "10s";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/openbao/raft";
    };
  };
  services.restic.backups.vpn.paths = [
    "/var/lib/netbird"
    "/var/lib/openbao/audit.log"
  ];
  services.logrotate.settings.openbao = {
    files = [ "/var/lib/openbao/audit.log" ];
    frequency = "daily";
    rotate = 14;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    create = "0600 openbao openbao";
    postrotate = "${pkgs.systemd}/bin/systemctl kill -s HUP openbao.service";
  };
}
