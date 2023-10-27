{ config, pkgs, lib, ... }:
let
  cfg = config.services.radarr;
  port = toString cfg.port;
in
{
  options = {
    services.radarr = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "radarr port to listen to locally";
        default = 7878;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.storagePath}/radarr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.radarr = {
      image = "lscr.io/linuxserver/radarr";
      ports = [ "${port}:7878" ];
      volumes = [
        "${config.persistPath}/radarr:/config"
        "/data:/data"
      ];
      extraOptions = [ "--network=host" ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx.virtualHosts."radarr.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
