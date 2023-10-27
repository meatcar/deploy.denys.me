{ config, pkgs, lib, ... }:
let
  cfg = config.services.ombi;
  port = toString cfg.port;
in
{
  config = {
    services.ombi.port = 3579;
    virtualisation.oci-containers.containers.ombi = {
      image = "ghcr.io/linuxserver/ombi";
      ports = [ "${port}:3579" ];
      volumes = [
        "${config.mine.persistPath}/ombi:/config"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
      };
      extraOptions = [ "--network=host" ];
    };

    services.nginx.virtualHosts."ombi.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
