{ config, lib, pkgs, ... }:
let
  acmeRoot = "${config.persistPath}/var/www/acme";
in
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "acme.${config.networking.hostName}@${config.netorking.domain}";
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
