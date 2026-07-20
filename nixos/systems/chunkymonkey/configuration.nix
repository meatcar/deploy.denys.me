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
    ../../modules/failure-notify.nix
    ./backups.nix
  ];

  mine = {
    username = "meatcar";
  };

  networking.hostName = "chunkymonkey";
  networking.hostId = "9f0d1484";
  networking.domain = "denys.me";

  # Set your time zone.
  time.timeZone = "America/Toronto";

  boot.initrd.systemd.enable = true;

  # No swap device on this host, so a memory spike goes straight to earlyoom
  # picking a victim. Compressed swap gives the kernel somewhere to put cold
  # pages first. Bounded well under RAM so it cannot itself cause pressure.
  zramSwap = {
    enable = true;
    memoryPercent = 15;
    memoryMax = 4 * 1024 * 1024 * 1024; # 4 GiB ceiling
  };

  # Failure alerting for the unattended jobs. Deliberately still off: it needs
  # modules/smtp.nix and real SES credentials, and the module asserts on that.
  # Turning this on is the last step of the SES milestone; until then, claiming
  # alerting works would be worse than admitting it does not.
  mine.failureNotify = {
    enable = false;
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
