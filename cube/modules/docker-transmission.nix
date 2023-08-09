{ config, pkgs, lib, ... }:
let
  cfg = config.services.docker-transmission;
in
{
  options = {
    services.docker-transmission.port = lib.mkOption {
      type = lib.types.int;
      description = "port transmission uses to listen locally";
      default = 9091;
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.persistPath}/transmission 0755 - - - -"
    ];
    virtualisation.oci-containers.containers.transmission = {
      image = "ghcr.io/linuxserver/transmission";
      dependsOn = [ "wireguard" ];
      volumes = [
        "${config.persistPath}/transmission:/config"
        "${config.storagePath}/System/transmission:${config.storagePath}/System/transmission"
        "${config.age.secrets.transmissionUser.path}:/username"
        "${config.age.secrets.transmissionPass.path}:/password"
      ];
      environment = {
        TZ = config.time.timeZone;
        FILE__USER = "/username";
        FILE__PASS = "/password";
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
      extraOptions = [
        "--network=container:wireguard"
      ];
    };
    virtualisation.oci-containers.containers.wireguard.ports = [
      "${toString cfg.port}:9091"
    ];
    services.nginx.virtualHosts."transmission.${config.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
