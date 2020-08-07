{ config, ... }: {
  services.sonarr = {
    enable = true;
    dataDir = "${config.persistPath}/var/lib/sonarr";
  };

  services.nginx.virtualHosts."sonarr.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8989";
  };
}
