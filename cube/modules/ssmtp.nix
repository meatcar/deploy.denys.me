{ config, pkgs, lib, ... }:
{
  options = {
    smtp = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "SMTP User";
      };
      host = lib.mkOption {
        type = lib.types.str;
        description = "SMTP Host";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "SMTP Port";
      };
      pass = lib.mkOption {
        type = lib.types.str;
        description = "SMTP Password";
      };
    };
  };
  config = {
    services.ssmtp = {
      enable = true;
      domain = config.domain;
      authUser = config.smtp.user;
      hostName = "${config.smtp.host}:${toString config.smtp.port}";
      useTLS = true;
      root = " root.${config.hostname}@${config.domain}";
      authPassFile = config.sops.secrets.ssmtpPass.path;
    };
  };
}
