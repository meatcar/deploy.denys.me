{ config, ... }:
let
  cfg = config.services.radarr;
in
{
  services.radarr = {
    enable = true;
    user = config.storageUser;
    group = config.storageGroup;
    dataDir = "${config.persistPath}/var/lib/radarr";
  };

  services.nginx.virtualHosts."radarr.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:7878";
  };
}
