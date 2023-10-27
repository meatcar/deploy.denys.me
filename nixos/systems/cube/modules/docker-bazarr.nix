{ config, pkgs, lib, ... }:
let
  cfg = config.services.bazarr;
  port = toString cfg.port;
in
{
  options = {
    services.bazarr = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "bazarr port to listen to locally";
        default = 6767;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mine.storagePath}/bazarr 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.bazarr = {
      image = "ghcr.io/linuxserver/bazarr";
      ports = [ "${port}:6767" ];
      volumes = [
        "${config.mine.persistPath}/bazarr:/config"
        "/data/Multimedia/Videos/Movies:/movies"
        "/data/Multimedia/Videos/TV Shows:/tv"
      ];
      extraOptions = [ "--network=host" ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
      };
    };

    services.nginx.virtualHosts."bazarr.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
