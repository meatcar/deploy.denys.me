{ config, modulesPath, pkgs, lib, ... }:
let
  fetchLines = url:
    lib.pipe url [
      builtins.fetchurl
      lib.fileContents
      (lib.splitString "\n")
    ];
in
{
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
    ./base.nix
    ./docker.nix
    ./backups.nix
    ./wireguard.nix
    ./mumble.nix
  ];

  environment.systemPackages = [
    pkgs.mosh
    pkgs.byobu
    pkgs.tmux
    pkgs.direnv
    pkgs.vim
  ];

  users.users.root.openssh.authorizedKeys.keys =
    fetchLines "https://github.com/meatcar.keys";

  users.users.meatcar = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys =
      fetchLines "https://github.com/meatcar.keys";
  };
}
