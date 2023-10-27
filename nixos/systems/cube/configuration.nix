{ config, pkgs, lib, ... }:
{
  imports = [
    ./options.nix
    ./secrets.nix
    ./hardware-configuration.nix
    ../../modules/base.nix
    ./modules/wireguard.nix
    ./modules/ssmtp.nix
    ./modules/smartd.nix
    ./modules/nginx.nix
    ../../modules/acme.nix
    ./modules/samba.nix
    ./modules/docker.nix
    # ./modules/docker-diun.nix
    # ./modules/docker-wireguard.nix
    # ./modules/docker-plex.nix
    # ./modules/docker-tautulli.nix
    # ./modules/docker-sonarr.nix
    # ./modules/docker-radarr.nix
    # ./modules/docker-ombi.nix
    # ./modules/docker-transmission.nix
    # ./modules/docker-jackett.nix
    # ./modules/docker-bazarr.nix
    # ./modules/docker-calibre-web.nix
    # ./modules/docker-readarr.nix
    # ./modules/docker-organizr.nix
    # ./modules/docker-scrutiny.nix
    # ./modules/docker-postgresql.nix
    # ./modules/docker-redis.nix
    # ./modules/docker-nextcloud.nix
  ];

  config = {
    networking.domain = "denys.me";
    networking.hostName = "cube";
    mine = {
      githubKeyUser = "meatcar";
      storagePath = "/data";
      persistPath = "/persist";
    };

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.tmp.useTmpfs = true;

    environment.systemPackages = with pkgs; [ pciutils usbutils ];
    environment.extraOutputsToInstall = [ "doc" "info" "devdoc" ]; # TODO: WHY?

    networking = {
      useDHCP = false;
      interfaces.enp2s0.useDHCP = true;
      interfaces.enp3s0 = {
        useDHCP = true;
      };
      nameservers = [ "1.1.1.1" "8.8.8.8" ];

      firewall.allowedTCPPorts = [ 80 443 ]; # TODO: move into relevant module
    };

    services.tailscale.enable = true;

    ids.uids.${config.mine.storageUser} = 997;
    ids.gids.${config.mine.storageUser} = 998;
    users = {
      mutableUsers = false;
      users =
        {
          root = {
            passwordFile = config.age.secrets.hashedPassword.path;
          };
          meatcar = {
            isNormalUser = true;
            passwordFile = config.age.secrets.hashedPassword.path;
            extraGroups = [ "wheel" "docker" config.mine.storageGroup ];
            openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
          };
          ${config.mine.storageUser} = {
            isSystemUser = true;
            uid = config.ids.uids.${config.mine.storageUser};
            group = config.mine.storageGroup;
            shell = pkgs.shadow;
          };
        };
      groups.${config.mine.storageGroup} = {
        gid = config.ids.gids.${config.mine.storageGroup};
      };
    };
  };
}
