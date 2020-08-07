{ config, ... }: {
  services.jackett = {
    enable = true;
    dataDir = "${config.persistPath}/var/lib/jackett";
  };

  services.nginx.virtualHosts."jackett.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:9117";
  };
}
