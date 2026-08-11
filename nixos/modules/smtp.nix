{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.mine.smtp;
  msmtprcTemplate = pkgs.writeText "msmtprc.template" ''
    defaults
    auth on
    tls on
    tls_starttls ${if cfg.startTls then "on" else "off"}
    aliases /etc/msmtp-aliases

    account default
    host ${cfg.host}
    port ${toString cfg.port}
    domain ${config.networking.domain}
    user @SMTP_USER@
    passwordeval ${pkgs.coreutils}/bin/cat ${cfg.passwordFile}
    from ${cfg.from}
  '';
in
{
  options = {
    mine = {
      smtp = {
        userFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to a file containing the SMTP username. Read at activation time.";
        };
        host = lib.mkOption {
          type = lib.types.str;
          description = "SMTP Host";
        };
        from = lib.mkOption {
          type = lib.types.str;
          description = "Envelope and default From address";
          default = "%U.${config.mine.notificationEmail}";
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "SMTP Port";
          default = 465;
        };
        startTls = lib.mkOption {
          type = lib.types.bool;
          description = "Use STARTTLS rather than implicit TLS";
          default = false;
        };
        passwordFile = lib.mkOption {
          type = lib.types.path;
          description = "The path to a file that contains the password";
        };
      };
    };
  };
  config = {
    programs.msmtp.enable = true;
    # programs.msmtp generates an /etc/msmtprc we don't want — we render our own
    # at activation time so the SMTP username can be sourced from cfg.userFile
    # (typically an agenix-decrypted file under /run/agenix) instead of being
    # baked into the nix store.
    environment.etc."msmtprc".enable = lib.mkForce false;

    environment.etc."msmtp-aliases".text = ''
      root: root.${config.mine.notificationEmail}
    '';

    system.activationScripts.msmtprc = lib.stringAfter [ "agenix" ] ''
      umask 077
      # cfg.userFile is an env-format file (KEY=value) shared with consumers
      # like diun that need it via environmentFiles. Source it to extract
      # SMTP_USER for msmtprc templating.
      . ${cfg.userFile}
      ${pkgs.gnused}/bin/sed "s|@SMTP_USER@|$SMTP_USER|g" ${msmtprcTemplate} > /etc/msmtprc
      chmod 0644 /etc/msmtprc
    '';
  };
}
