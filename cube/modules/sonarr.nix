{ config, ... }:
let
  cfg = config.services.sonarr;
in
{
  services.sonarr = {
    enable = true;
    user = config.storageUser;
    group = config.storageGroup;
    dataDir = "${config.persistPath}/var/lib/sonarr";
  };

  services.nginx.virtualHosts."sonarr.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8989";
  };
}
