{ config, pkgs, lib, ... }:
let
  cfg = config.services.readarr;
  port = toString cfg.port;
in
{
  options = {
    services.readarr = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "readarr port to listen to locally";
        default = 8787;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.storagePath}/readarr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.readarr = {
      image = "lscr.io/linuxserver/readarr:nightly";
      ports = [ "${port}:8787" ];
      volumes = [
        "${config.persistPath}/readarr:/config"
        "/data:/data"
      ];
      extraOptions = [ "--network=host" ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx.virtualHosts."readarr.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
