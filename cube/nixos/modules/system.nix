{ config, lib, pkgs, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.tmpOnTmpfs = true;

  networking.hostName = config.hostname;

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp7s0.useDHCP = true;
  networking.interfaces.enp8s0 = {
    useDHCP = false;
    ipv4.addresses = [{ address = "192.168.0.9"; prefixLength = 24; }];
  };
  networking.defaultGateway = {
    address = "192.168.0.1";
    interface = "enp8s0";
  };
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  time.timeZone = "America/Toronto";

  environment.extraOutputsToInstall = [ "doc" "info" "devdoc" ];
  environment.systemPackages = with pkgs; [
    wget
    tree
    vim
    tmux
    byobu
    mosh
    pciutils
    usbutils
    git
    htop
  ];

  services.openssh.enable = true;

  programs = {
    mosh.enable = true;
    command-not-found.enable = true;
  };

  users = {
    mutableUsers = false;
    users =
      let
        fetchLines = url:
          lib.pipe url [
            builtins.fetchurl
            lib.fileContents
            (lib.splitString "\n")
          ];
      in
      {
        root = {
          hashedPassword = config.hashedPassword;
          openssh.authorizedKeys.keys = fetchLines config.sshKeysUrl;
        };
        meatcar = {
          isNormalUser = true;
          hashedPassword = config.hashedPassword;
          extraGroups = [ "wheel" "docker" ];
          openssh.authorizedKeys.keys = fetchLines config.sshKeysUrl;
        };
      };
  };

  nixpkgs.config.allowUnfree = true;
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 1w";
  };
  system.autoUpgrade.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?

}
