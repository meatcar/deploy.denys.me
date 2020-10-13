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
      pass = lib.mkOption {
        type = lib.types.str;
        description = "SMTP Password";
      };
    };
  };
  config = {
    systemd.tmpfiles.rules = [
      "f /run/ssmtpPass 0600 - - - ${config.smtp.pass}"
    ];
    services.ssmtp = {
      enable = true;
      domain = "${config.domain}";
      authUser = "${config.smtp.user}";
      hostName = "${config.smtp.host}";
      useTLS = true;
      root = "root-${config.hostname}@${config.domain}";
      authPassFile = "/run/ssmtpPass";
    };
  };
}
