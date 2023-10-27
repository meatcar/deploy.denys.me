{ config, pkgs, lib, ... }:
let
  cfg = config.services.redis.servers.default;
  port = toString cfg.port;
  dataDir = "${config.mine.persistPath}/redis";
in
{
  config = {
    services.redis.servers.default.port = 6379;
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 - - - -"
    ];
    virtualisation.oci-containers.containers.redis = {
      image = "redis";
      ports = [ "${port}:6379" ];
      volumes = [
        "${dataDir}:/data"
        "${config.age.secrets.redisConf.path}:/usr/local/etc/redis/redis.conf"
      ];
      cmd = [ "/bin/sh" "-c" "redis-server /usr/local/etc/redis/redis.conf" ];
      extraOptions = [ "--network=nextcloud" ];
    };
  };
}
