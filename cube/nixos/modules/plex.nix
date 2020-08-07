{ config, pkgs, ... }:
{
  config = {
    systemd.tmpfiles.rules = [
      "L /var/lib/plex - - - - ${config.persistPath}/var/lib/plex"
    ];

    nixpkgs.config.allowUnfree = true;

    services.plex = {
      enable = true;
    };

    services.nginx.virtualHosts."plex.${config.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:32400";
    };
  };
}
