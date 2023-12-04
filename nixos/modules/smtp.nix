{ config, pkgs, lib, ... }:
let
  cfg = config.mine.smtp;
in
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
        passwordFile = lib.mkOption {
          type = lib.types.path;
          description = "The path to a file that contains the password";
        };
      };
    };
  };
  config = {
    programs.msmtp = {
      enable = true;
      accounts.default = {
        inherit (config.networking) domain;
        inherit (cfg) user host port;
        auth = true;
        tls = true;
        tls_starttls = false;
        passwordeval = "${pkgs.coreutils}/bin/cat ${cfg.passwordFile}";
        from = "%U.${config.networking.hostName}@${config.networking.domain}";
        aliases = pkgs.writeText "msmtp-aliases" ''
          root: root-${config.networking.hostName}@${config.networking.domain}
        '';
      };
    };
  };
}
