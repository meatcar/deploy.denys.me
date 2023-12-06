{ config, pkgs, ... }:
{
  imports = [
    ./secrets.nix
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/wireguard-client.nix
    ../../modules/smtp.nix
    ../../modules/smartd.nix
    ../../modules/acme.nix
    ../../modules/samba.nix
    ../../modules/docker.nix
    # ./modules/docker-diun.nix
    ./modules/docker-wireguard.nix
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
    ./modules/nginx.nix
    ../../modules/zfs.nix
  ];

  config = {
    networking.domain = "denys.me";
    networking.hostName = "cube";
    networking.hostId = "611b4046";
    time.timeZone = "America/Toronto";
    mine = {
      username = "meatcar";
      githubKeyUser = "meatcar";
      storagePath = "/data";
      persistPath = "/persist";
      networking.wireguard.serverPort = 51821;
      networking.wireguard.ipIndex = 4;
      smtp.passwordFile = "${config.age.secrets.ssmtpPass.path}";
    };


    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.extraInstallCommands = ''
      # backup boot
      find /boot-backup -mindepth 1 -delete
      cp -r /boot/* /boot-backup
    '';
    boot.loader.efi.canTouchEfiVariables = true;
    boot.tmp.useTmpfs = true;

    environment.systemPackages = with pkgs; [ pciutils usbutils ];

    networking = {
      useDHCP = false;
      interfaces.enp2s0.useDHCP = true;
      interfaces.enp3s0 = {
        useDHCP = true;
      };
      nameservers = [ "1.1.1.1" "8.8.8.8" ];
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
