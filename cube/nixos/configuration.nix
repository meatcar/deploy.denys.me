{ config, pkgs, lib, ... }:
{
  options =
    let
      inherit (lib) mkOption types;
    in
    {
      domain = mkOption {
        type = types.str;
        description = "the base domain name of server";
      };
      hostname = mkOption {
        type = types.str;
        description = "the hostname of the server";
      };
      hashedPassword = mkOption {
        type = types.str;
        description = "the hashed password, generated with `nix-shell -p mkpasswd --command 'mkpasswd -m sha-512`";
      };
      sshKeysUrl = mkOption {
        type = types.str;
        description = "the URL of the ssh keys to authorize";
      };
      fqdn = mkOption {
        type = types.str;
        default = "${config.hostname}.${config.domain}";
        description = "the Fully Qualified Domain Name of the server";
      };
      storagePath = mkOption {
        type = types.path;
        description = "Mountpoint of main storage array";
      };
      persistPath = mkOption {
        type = types.path;
        description = "Mountpoint of main persisted system storeage";
      };
    };

  imports =
    [
      ./secrets.nix
      ./hardware-configuration.nix
      ./modules/system.nix
      ./modules/ssmtp.nix
      ./modules/docker.nix
      ./modules/dynamicdns.nix
      ./modules/acme.nix
      ./modules/samba.nix
      ./modules/plex.nix
      ./modules/tautulli.nix
      ./modules/jackett.nix
      ./modules/sonarr.nix
      ./modules/deluge.nix
    ];

  config = {
    domain = "denys.me";
    hostname = "cube";
    sshKeysUrl = "https://github.com/meatcar.keys";
    storagePath = "/data";
    persistPath = "/persist";

    services.nginx.enable = true;
    networking = {
      firewall.allowedTCPPorts = [ 80 443 ];
    };
  };
}
