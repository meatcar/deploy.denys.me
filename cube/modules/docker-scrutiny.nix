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
      image = "ghcr.io/linuxserver/scrutiny";
      ports = [ "${port}:8080" ];
      volumes = [
        "${config.persistPath}/scrutiny:/config"
        "/run/dev:/run/dev:ro"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
        DOCKER_MODS = "linuxserver/scrutiny:calibre";
        SCRUTINY_API_ENDPOINT = "http://localhost:8080";
        SCRUTINY_WEB = "true";
        SCRUTINY_COLLECTOR = "true";
      };
      extraOptions = [
        "--device"
        "/dev/sda:/dev/sda"
        "--device"
        "/dev/sdb:/dev/sdb"
        "--device"
        "/dev/sdc:/dev/sdc"
        "--device"
        "/dev/sdd:/dev/sdd"
        "--device"
        "/dev/sde:/dev/sde"
        "--device"
        "/dev/sdf:/dev/sdf"
        "--cap-add=SYS_RAWIO"
        "--cap-add=SYS_ADMIN" # for nvme drives
      ];
    };

    services.nginx.virtualHosts."scrutiny.${config.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
