{ config, pkgs, ... }:
let
  cfg = config.services.transmission;
in
{
  services.transmission = {
    enable = true;
    user = config.storageUser;
    group = config.storageGroup;
    home = "${config.persistPath}/transmission";
    settings = {
      download-dir = "${config.storagePath}/System/transmission/Downloads";
      incomplete-dir = "${config.storagePath}/System/transmission/.incomplete";
      incomplete-dir-enabled = true;
      blocklist-enabled = true;
      blocklist-url = "https://github.com/sahsu/transmission-blocklist/releases/latest/download/blocklist.gz";
      ratio-limit = "0";
      ratio-limit-enabled = true;
    };
    openFirewall = true;
  };
  services.nginx.virtualHosts."transmission.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString cfg.settings.rpc-port}";
  };
}
