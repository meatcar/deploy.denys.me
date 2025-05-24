{
  config,
  lib,
  pkgs,
  ...
}:
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "acme.${config.mine.notificationEmail}";
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
