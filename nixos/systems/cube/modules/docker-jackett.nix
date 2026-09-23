{
  config,
  ...
}:
let
  cfg = config.services.jackett;
in
{
  config = {
    virtualisation.oci-containers.containers.jackett = {
      image = "ghcr.io/linuxserver/jackett";
      dependsOn = [ "gluetun" ];
      networks = [ "container:gluetun" ];
      volumes = [
        "${config.mine.persistPath}/jackett:/config"
      ];
      environment = {
        TZ = config.time.timeZone;
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
        AUTO_UPDATE = "true";
      };
    };

    virtualisation.oci-containers.containers.gluetun.ports = [
      "127.0.0.1:${toString cfg.port}:9117"
    ];

    services.nginx.virtualHosts."jackett.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
