{ config, pkgs, lib, ... }:
{
  imports = [
    ./options.nix
    ./hardware-configuration.nix
    ./modules/system.nix
    ./modules/wireguard.nix
    ./modules/ssmtp.nix
    ./modules/smartd.nix
    ./modules/nginx.nix
    ./modules/acme.nix
    ./modules/samba.nix
    ./modules/docker.nix
    ./modules/docker-diun.nix
    ./modules/docker-wireguard.nix
    ./modules/docker-plex.nix
    ./modules/docker-tautulli.nix
    ./modules/docker-sonarr.nix
    ./modules/docker-radarr.nix
    ./modules/docker-ombi.nix
    ./modules/docker-transmission.nix
    ./modules/docker-jackett.nix
    ./modules/docker-bazarr.nix
    ./modules/docker-calibre-web.nix
    ./modules/docker-readarr.nix
    ./modules/docker-organizr.nix
    ./modules/docker-scrutiny.nix
    ./modules/docker-postgresql.nix
    ./modules/docker-redis.nix
    ./modules/docker-nextcloud.nix
  ];

  config = {
    networking.domain = "denys.me";
    networking.hostName = "cube";
    sshKeysUrl = "https://github.com/meatcar.keys";
    storagePath = "/data";
    persistPath = "/persist";

    networking = {
      firewall.allowedTCPPorts = [ 80 443 ];
    };

    services.tailscale.enable = true;
  };
}
