{ config, pkgs, lib, ... }:
{
  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];

  security.sudo.wheelNeedsPassword = false;
  nix.trustedUsers = [ "root" "@wheel" ];
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 1w";
  };
  nix.autoOptimiseStore = true;
  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.autoUpgrade = {
    enable = false;
    flake = "github:meatcar/deploy.denys.me#default";
    flags = [ "--update-input" "nixpkgs" ];
  };


  services.sshd.enable = true;
  programs.mosh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
