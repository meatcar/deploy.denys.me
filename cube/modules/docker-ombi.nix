{ config, pkgs, lib, ... }:
let
  cfg = config.services.ombi;
  port = toString cfg.port;
in
{
  options = {
    services.ombi = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "ombi port to listen to locally";
        default = 3579;
      };
    };
  };

  config = {
    virtualisation.oci-containers.containers.ombi = {
      image = "ghcr.io/linuxserver/ombi";
      ports = [ "3579:${port}" ];
      volumes = [
        "${config.persistPath}/ombi:/config"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
      extraOptions = [ "--network=host" ];
    };

    services.nginx.virtualHosts."ombi.${config.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
