{ config, modulesPath, pkgs, lib, ... }:
let
  sshKeys = lib.pipe
    {
      url = "https://github.com/${config.mine.githubKeyUser}.keys";
      sha256 = "sha256:1g214y4ibdnxavsbrhds1hwxz30lff808nh2kzw3wxwkb8f1z1yd";
    }
    [
      builtins.fetchurl
      builtins.readFile
      (lib.splitString "\n")
    ];
in
{
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
    ./secrets.nix # provided by terraform
    ./base.nix
    ./docker.nix
    ./docker-fix.nix
    ./backups.nix
    ./wireguard.nix
    ./acme.nix
    ./nginx.nix
    ./mumble.nix
    ./znc.nix
    ./nodered.nix
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
    mine = {
      domain = "denys.me";
      githubKeyUser = "meatcar";
      znc = {
        enable = true;
        users = {
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
      };
      nodered.enable = true;
    };

    time.timeZone = "America/Toronto";

    environment.systemPackages =
      [ pkgs.mosh pkgs.byobu pkgs.tmux pkgs.direnv pkgs.vim pkgs.git ];

    users.users.root.openssh.authorizedKeys.keys = sshKeys;

    users.users.meatcar = {
      isNormalUser = true;
      extraGroups = [ "wheel" "docker" "nginx" ];
      hashedPassword =
        "$6$TW7fMuG2cMYbWDC$p0t7uFxePu/U.Lp8MUp0tgoJZh.EL7MkC3SG5jsNCIXkh2S.LA8wxnUEZpG4Mnvk/C3WOMKz35YXCC0XDkZWm/";
      openssh.authorizedKeys.keys = sshKeys;
    };
  };
}
