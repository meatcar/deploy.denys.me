# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, modulesPath, ... }:
{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/oracle-cloud.nix
      ../../modules/base.nix
      ../../modules/tailscale.nix
      ../../modules/docker.nix
      ../../modules/zfs.nix
    ];

  mine = {
    username = "meatcar";
    githubKeyUser = "meatcar";
  };

  networking.hostName = "chunkymonkey";
  networking.hostId = "9f0d1484";

  # Set your time zone.
  time.timeZone = "America/Toronto";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "nginx" ];
    hashedPassword =
      "$6$TW7fMuG2cMYbWDC$p0t7uFxePu/U.Lp8MUp0tgoJZh.EL7MkC3SG5jsNCIXkh2S.LA8wxnUEZpG4Mnvk/C3WOMKz35YXCC0XDkZWm/";
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}
