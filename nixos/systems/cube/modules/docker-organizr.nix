{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.organizr;
  port = toString cfg.port;
in {
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
      "d ${config.mine.storagePath}/organizr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.organizr = {
      image = "ghcr.io/organizr/organizr";
      ports = ["${port}:80"];
      volumes = [
        "${config.mine.persistPath}/organizr:/config"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
      };
    };

    services.nginx.virtualHosts."organizr.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
