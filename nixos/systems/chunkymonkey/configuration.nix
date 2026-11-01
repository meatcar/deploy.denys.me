{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./agenix.nix
    ../../modules/oracle-cloud.nix
    ../../modules/base.nix
    ../../modules/tailscale.nix
    ../../modules/netbird.nix
    ../../modules/docker.nix
    ../../modules/quadlets
    ../../modules/zfs.nix
    ../../modules/docker-transit-dashboard.nix
    ../../modules/backups.nix
    ../../modules/smtp.nix
    ../../modules/failure-notify.nix
    ./backups.nix
  ];

  mine = {
    username = "meatcar";
    cliProxyApi.deploymentFile = ./cli-proxy-api.json;
    smtp = {
      host = "email-smtp.ca-central-1.amazonaws.com";
      from = "billing@denys.me";
      port = 587;
      startTls = true;
      userFile = config.age.secrets.sesSmtpUser.path;
      passwordFile = config.age.secrets.sesSmtpPass.path;
    };
  };

  networking.hostName = "chunkymonkey";
  networking.hostId = "9f0d1484";
  networking.domain = "denys.me";

  time.timeZone = "America/Toronto";

  boot.initrd.systemd.enable = true;

  services.openssh = {
    openFirewall = false;
    settings.PermitRootLogin = "no";
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 22 ];

  # NOTE: No swap device; zram holds cold pages before earlyoom acts.
  zramSwap = {
    enable = true;
    memoryPercent = 15;
    memoryMax = 4 * 1024 * 1024 * 1024;
  };
  # NOTE: Rootless user services cannot lower OOMScoreAdjust.
  services.earlyoom.extraArgs = [
    "--avoid"
    "(^|/)(mysqld|postgres)$"
  ];

  mine.failureNotify = {
    enable = true;
    to = "billing@denys.me";
    units = [
      "restic-backups-persist"
      "zfs-scrub"
      "nix-gc"
    ];
  };

  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      # NOTE: Not "docker": root-equivalent, and agent sessions run as this user. Use `sudo docker`.
      "nginx"
    ];
    hashedPasswordFile = config.age.secrets.hashedPassword.path;
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}
