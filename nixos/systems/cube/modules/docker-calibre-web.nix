{ config, pkgs, lib, ... }:
let
  cfg = config.services.calibre-web;
  port = toString cfg.port;
in
{
  options = {
    services.calibre-web = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "calibre-web port to listen to locally";
        default = 8083;
      };
    };
  };

  config = {
    virtualisation.oci-containers.containers.calibre-web = {
      image = "ghcr.io/linuxserver/calibre-web";
      ports = [ "${port}:8083" ];
      volumes = [
        "${config.mine.persistPath}/calibre-web:/config"
        "${config.mine.storagePath}/Multimedia/Books:/books"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
        DOCKER_MODS = "linuxserver/calibre-web:calibre";
      };
    };

    services.nginx.virtualHosts."calibre-web.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
