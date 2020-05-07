{ config, lib, ... }:
{
  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];

  system.autoUpgrade.enable = true;
  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-20.03";
  nix.gc.automatic = true;
  nix.autoOptimiseStore = true;

  services.sshd.enable = true;
  programs.mosh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
