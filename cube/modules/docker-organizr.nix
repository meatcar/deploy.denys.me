{ config, pkgs, lib, ... }:
let
  cfg = config.services.organizr;
  port = toString cfg.port;
in
{
  options = {
    services.organizr = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "organizr port to listen to locally";
        default = 8191;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.storagePath}/organizr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.organizr = {
      image = "ghcr.io/organizr/organizr";
      ports = [ "${port}:80" ];
      volumes = [
        "${config.persistPath}/organizr:/config"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx.virtualHosts."organizr.${config.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
