{ config, pkgs, lib, ... }:
{
  options = {
    mine = {
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
      };
    };
  };
  config = {
    programs.msmtp = {
      enable = true;
      accounts.default = {
        inherit (config.networking) domain;
        inherit (config.mine.smtp) user host port;
        auth = true;
        tls = true;
        passwordeval = "${pkgs.coreutils}/bin/cat ${config.age.secrets.ssmtpPass.path}";
        from = "%U.${config.networking.hostName}@${config.networking.domain}";
        aliases = pkgs.writeText "msmtp-aliases" ''
          root: root-${config.networking.hostName}@${config.networking.domain}
        '';
      };
    };
  };
}
