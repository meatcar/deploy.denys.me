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
    ./modules/plex.nix
    ./modules/tautulli.nix
    ./modules/sonarr.nix
    ./modules/radarr.nix
    ./modules/docker.nix
    ./modules/docker-diun.nix
    ./modules/docker-wireguard.nix
    ./modules/docker-ombi.nix
    ./modules/docker-transmission.nix
    ./modules/docker-jackett.nix
    ./modules/docker-bazarr.nix
    ./modules/docker-calibre-web.nix
    ./modules/docker-readarr.nix
    ./modules/docker-organizr.nix
    ./modules/docker-scrutiny.nix
  ];

  config = {
    domain = "denys.me";
    hostname = "cube";
    sshKeysUrl = "https://github.com/meatcar.keys";
    storagePath = "/data";
    persistPath = "/persist";

    networking = {
      firewall.allowedTCPPorts = [ 80 443 ];
    };
  };
}
