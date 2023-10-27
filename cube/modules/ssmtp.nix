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
        default = 565;
      };
      pass = lib.mkOption {
        type = lib.types.str;
        description = "SMTP Password";
      };
    };
  };
  config = {
    programs.msmtp = {
      enable = true;
      accounts.default = {
        inherit (config) domain;
        inherit (config.smtp) user host port;
        auth = true;
        tls = true;
        passwordeval = "${pkgs.coreutils}/bin/cat ${config.age.secrets.ssmtpPass.path}";
        from = "%U.${config.networking.hostName}@${config.networking.domain}";
        aliases = pkgs.writeTextFile "msmtp-aliases" ''
          root: root-${config.networking.hostName}@${config.networking.domain}
        '';
      };
    };
  };
}
