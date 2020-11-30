{ config, pkgs, ... }:
let
  cfg = config.services.tautulli;
in
{
  services.tautulli = {
    enable = true;
    dataDir = "${config.persistPath}/var/lib/tautulli";
    configFile = "${cfg.dataDir}/config.ini";
  };

  services.nginx.virtualHosts."tautulli.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/newsletters".root = "${cfg.dataDir}/newsletters";
    locations."/".proxyPass = "http://127.0.0.1:8181";
  };
}
