{ config, modulesPath, pkgs, lib, ... }:
{
  imports = [
    ./secrets.nix # provided by terraform
    ../../modules/base.nix
    ../../modules/digitalocean.nix
    ../../modules/docker.nix
    ../../modules/docker-fix.nix
    ../../modules/backups.nix
    ../../modules/wireguard.nix
    ../../modules/tailscale.nix
    ../../modules/acme.nix
    ../../modules/nginx.nix
    ../../modules/mumble.nix
    ../../modules/znc.nix
    ../../modules/nodered.nix
  ];

  mine = {
    username = "meatcar";
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

  networking = {
    domain = "denys.me";
    hostName = "to";
  };

  time.timeZone = "America/Toronto";

  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "nginx" ];
    hashedPassword =
      "$6$TW7fMuG2cMYbWDC$p0t7uFxePu/U.Lp8MUp0tgoJZh.EL7MkC3SG5jsNCIXkh2S.LA8wxnUEZpG4Mnvk/C3WOMKz35YXCC0XDkZWm/";
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}