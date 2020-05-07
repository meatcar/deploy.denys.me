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
    hashedPassword = "$6$TW7fMuG2cMYbWDC$p0t7uFxePu/U.Lp8MUp0tgoJZh.EL7MkC3SG5jsNCIXkh2S.LA8wxnUEZpG4Mnvk/C3WOMKz35YXCC0XDkZWm/";
    openssh.authorizedKeys.keys =
      fetchLines "https://github.com/meatcar.keys";
  };
}
