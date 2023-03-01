{ config, pkgs, lib, ... }:
let
  cfg = config.services.postgresql;
  port = toString cfg.port;
  dataDir = "${config.persistPath}/postgres";
in
{
  config = {
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 - - - -"
    ];
    virtualisation.oci-containers.containers.postgres = {
      image = "postgres:14";
      ports = [ "${port}:5432" ];
      volumes = [
        "${dataDir}:/var/lib/postgresql/data"
        "${config.age.secrets.postgresPass.path}:${config.age.secrets.postgresPass.path}"
        "${config.age.secrets.nextcloudPgPass.path}:${config.age.secrets.nextcloudPgPass.path}"
      ];
      environment = {
        POSTGRES_PASSWORD_FILE = config.age.secrets.postgresPass.path;
      };
      extraOptions = [ "--network=nextcloud" ];
    };
  };
}

