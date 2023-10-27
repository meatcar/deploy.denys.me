{ config, pkgs, lib, ... }:
let
  cfg = config.services.jackett;
in
{
  options = {
    services.jackett = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "jackett port to listen to locally";
        default = 9117;
      };
    };
  };

  config = {
    virtualisation.oci-containers.containers.jackett = {
      image = "ghcr.io/linuxserver/jackett";
      dependsOn = [ "wireguard" ];
      volumes = [
        "${config.persistPath}/jackett:/config"
      ];
      environment = {
        TZ = config.time.timeZone;
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
        AUTO_UPDATE = "true";
      };
      extraOptions = [
        "--network=container:wireguard"
      ];
    };

    virtualisation.oci-containers.containers.wireguard.ports = [
      "${toString cfg.port}:9117"
    ];

    services.nginx.virtualHosts."jackett.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
