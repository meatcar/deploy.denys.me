{ config, lib, pkgs, ... }:
let
  acmeRoot = "${config.persistPath}/var/www/acme";
in
{
  security.acme = {
    acceptTerms = true;
    email = "acme.${config.hostname}@${config.domain}";
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
