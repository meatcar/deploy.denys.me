{ config, modulesPath, pkgs, lib, ... }:
let
  fetchLines = url:
    lib.pipe url [ builtins.fetchurl lib.fileContents (lib.splitString "\n") ];
in
{
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
    ./secrets.nix # provided by terraform
    ./base.nix
    ./docker.nix
    ./backups.nix
    ./wireguard.nix
    ./acme.nix
    ./nginx.nix
    ./mumble.nix
    ./znc.nix
  ];

  options.mine = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "The base domain to serve";
    };

    githubKeyUser = lib.mkOption {
      type = lib.types.str;
      description = "The github user that provides the ssh keys to authorize.";
    };
  };

  config = {
    mine.domain = "denys.me";
    mine.githubKeyUser = "meatcar";
    mine.znc.users = {
      meatcar = {
        extraConfig = {
          Admin = true;
          RealName = "Denys Pavlov";
        };
        networks = {
          freenode = { extraConfig = { Server = "chat.freenode.net +7000"; }; };
        };
      };
    };

    time.timeZone = "America/Toronto";

    environment.systemPackages =
      [ pkgs.mosh pkgs.byobu pkgs.tmux pkgs.direnv pkgs.vim ];

    users.users.root.openssh.authorizedKeys.keys =
      fetchLines "https://github.com/${config.mine.githubKeyUser}.keys";

    users.users.meatcar = {
      isNormalUser = true;
      extraGroups = [ "wheel" "docker" ];
      hashedPassword =
        "!";
      openssh.authorizedKeys.keys =
        fetchLines "https://github.com/${config.mine.githubKeyUser}.keys";
    };
  };
}
