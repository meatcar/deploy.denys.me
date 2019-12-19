{ config, modulesPath, pkgs, lib, ... }:
{
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
    ./base.nix
    ./wireguard.nix
  ];

  environment.systemPackages = [ pkgs.mosh ];

  users.users.root.openssh.authorizedKeys.keys =
    lib.splitString "\n"
      (lib.removeSuffix "\n" (builtins.readFile (builtins.fetchurl "https://github.com/meatcar.keys")));
}
