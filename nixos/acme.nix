{ config, lib, pkgs, ... }:

{
  security.acme = {
    acceptTerms = true;
    email = "acme.${config.mine.domain}@denys.me";
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
