{ config, pkgs, ... }:
{
  services.tautulli = {
    enable = true;
    dataDir = "${config.persistPath}/var/lib/tautulli";
    configFile = "${config.persistPath}/var/lib/tautulli/config.ini";
  };

  services.nginx.virtualHosts."tautulli.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8181";
  };
}
