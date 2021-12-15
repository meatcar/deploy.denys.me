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
  networking.interfaces.enp2s0.useDHCP = true;
  networking.interfaces.enp3s0 = {
    useDHCP = true;
    #ipv4.addresses = [{ address = "192.168.0.9"; prefixLength = 24; }];
  };
  #networking.defaultGateway = {
  #  address = "192.168.0.1";
  #  interface = "enp3s0";
  #};
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  time.timeZone = "America/Toronto";

  environment.extraOutputsToInstall = [ "doc" "info" "devdoc" ];
  environment.systemPackages = with pkgs; [
    wget
    tree
    vim
    tmux
    byobu
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

  services.eternal-terminal.enable = true;
  networking.firewall.allowedTCPPorts = [ config.services.eternal-terminal.port ];

  ids.uids.${config.storageUser} = 997;
  ids.gids.${config.storageUser} = 998;
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
          passwordFile = config.sops.secrets.hashedPassword.path;
          openssh.authorizedKeys.keys = fetchLines config.sshKeysUrl;
        };
        meatcar = {
          isNormalUser = true;
          passwordFile = config.sops.secrets.hashedPassword.path;
          extraGroups = [ "wheel" "docker" config.storageGroup ];
          openssh.authorizedKeys.keys = fetchLines config.sshKeysUrl;
        };
        ${config.storageUser} = {
          isSystemUser = true;
          uid = config.ids.uids.${config.storageUser};
          group = config.storageGroup;
          shell = pkgs.nologin;
        };
      };
    groups.${config.storageGroup} = {
      gid = config.ids.gids.${config.storageGroup};
    };
  };

  nixpkgs.config.allowUnfree = true;
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 1w";
  };
  nix.package = pkgs.nixFlakes;
  system.autoUpgrade = {
    enable = false;
    flake = "github:meatcar/cube.denys.me";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?

}
