# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "cube.denys.me";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp7s0.useDHCP = true;
  networking.interfaces.enp8s0.useDHCP = true;

  time.timeZone = "America/Toronto";

  environment.systemPackages = with pkgs; [
    wget
    vim
    tmux
    byobu
    mosh
    pciutils
    usbutils
  ];

  services.openssh.enable = true;
  programs.mosh.enable = true;
  programs.command-not-found.enable = true;

  users.users.root.openssh.authorizedKeys.keys =
    lib.splitString "\n"
      (lib.removeSuffix "\n" (builtins.readFile (builtins.fetchurl "https://github.com/meatcar.keys")));

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?
}
