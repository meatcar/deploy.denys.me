# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
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
    ../../modules/docker.nix # still needed: transit-dashboard runs on docker
    ../../modules/quadlets # default.nix wires pod user + all quadlet services
    ../../modules/zfs.nix
    ../../modules/docker-transit-dashboard.nix
    ../../modules/backups.nix
    ../../modules/smtp.nix
    ../../modules/failure-notify.nix
    ./backups.nix
  ];

  mine = {
    username = "meatcar";
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

  # Set your time zone.
  time.timeZone = "America/Toronto";

  boot.initrd.systemd.enable = true;

  # Administrative SSH is available only over the tailnet. OCI no longer
  # exposes public TCP/22; keep the host firewall aligned with that boundary.
  services.openssh = {
    openFirewall = false;
    settings.PermitRootLogin = "no";
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # No swap device on this host, so a memory spike goes straight to earlyoom
  # picking a victim. Compressed swap gives the kernel somewhere to put cold
  # pages first. Bounded well under RAM so it cannot itself cause pressure.
  zramSwap = {
    enable = true;
    memoryPercent = 15;
    memoryMax = 4 * 1024 * 1024 * 1024; # 4 GiB ceiling
  };
  # Rootless user services cannot lower OOMScoreAdjust. Ask earlyoom itself to
  # avoid the database processes while their MemoryHigh/MemoryMax limits bound
  # their footprint.
  services.earlyoom.extraArgs = [
    "--avoid"
    "(^|/)(mysqld|postgres)$"
  ];

  # Route unattended-service failures through the production SES account.
  mine.failureNotify = {
    enable = true;
    to = "billing@denys.me";
    units = [
      "restic-backups-persist"
      "zfs-scrub"
      "nix-gc"
    ];
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      # Deliberately NOT in "docker": membership is root-equivalent (it can bind
      # mount / into a container), and this host also runs interactive agent
      # sessions as this user. Use `sudo docker` instead.
      "nginx"
    ];
    hashedPasswordFile = config.age.secrets.hashedPassword.path;
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}
