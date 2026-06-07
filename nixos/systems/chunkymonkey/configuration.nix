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
    ../../modules/docker.nix
    ../../modules/zfs.nix
    ../../modules/docker-transit-dashboard.nix
  ];

  mine = {
    username = "meatcar";
    githubKeyUser = "meatcar";
  };

  networking.hostName = "chunkymonkey";
  networking.hostId = "9f0d1484";
  networking.domain = "denys.me";

  # Set your time zone.
  time.timeZone = "America/Toronto";

  # 26.05 defaults systemd stage-1 initrd; pin scripted until ZFS-root migration
  # is tested. Revisit before 26.11 (when scripted initrd is removed).
  boot.initrd.systemd.enable = false;

  # Define a user account. Don’t forget to set a password with ‘passwd’.
  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "nginx"
    ];
    hashedPasswordFile = config.age.secrets.hashedPassword.path;
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}
