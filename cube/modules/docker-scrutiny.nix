{ config, pkgs, lib, ... }:
let
  cfg = config.services.scrutiny;
  port = toString cfg.port;
in
{
  options = {
    services.scrutiny = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "scrutiny port to listen to locally";
        default = 9912;
      };
    };
  };

  config = {
    virtualisation.oci-containers.containers.scrutiny = {
      image = "ghcr.io/analogj/scrutiny:master-omnibus";
      ports = [ "${port}:8080" ];
      volumes = [
        "${config.persistPath}/scrutiny/config:/opt/scrutiny/config"
        "${config.persistPath}/scrutiny/influxdb2:/opt/scrutiny/influxdb"
        "/run/dev:/run/dev:ro"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
      extraOptions = [
        "--device=/dev/sda"
        "--device=/dev/sdb"
        "--device=/dev/sdc"
        "--device=/dev/sdd"
        "--device=/dev/sde"
        "--device=/dev/sdf"
        "--device=/dev/sdg"
        "--device=/dev/sdh"
        "--device=/dev/sdi"
        "--cap-add=SYS_RAWIO"
        "--cap-add=SYS_ADMIN" # for nvme drives
      ];
    };

    services.nginx.virtualHosts."scrutiny.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
