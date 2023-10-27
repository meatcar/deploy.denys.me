{ config, pkgs, lib, ... }:
let
  cfg = config.services.sonarr;
  port = toString cfg.port;
in
{
  options = {
    services.sonarr = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "sonarr port to listen to locally";
        default = 8989;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.storagePath}/sonarr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.sonarr = {
      image = "lscr.io/linuxserver/sonarr";
      ports = [ "${port}:8989" ];
      volumes = [
        "${config.persistPath}/sonarr:/config"
        "/data:/data"
      ];
      extraOptions = [ "--network=host" ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx.virtualHosts."sonarr.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
