{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.diun;
in
{
  options = {
    services.diun.port = lib.mkOption {
      type = lib.types.int;
      description = "port diun uses to listen locally";
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mine.persistPath}/diun 0750 - - - -"
    ];
    virtualisation.oci-containers.containers.diun =
      let
        email = "${config.mine.notificationEmail}";
        configFile = pkgs.writeText "duin-config.yml" ''
          watch:
            workers: 10
            schedule: "0 */6 * * *"
          providers:
            docker:
              watchStopped: true
              watchByDefault: true
          notif:
            mail:
              host: ${config.mine.smtp.host}
              port: ${toString config.mine.smtp.port}
              ssl: true
              localName: ${config.networking.fqdn}
              passwordFile: /smtppass
              from: diun.${email}
              to: admin.${email}
        '';
      in
      {
        image = "crazymax/diun";
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
          "${config.mine.persistPath}/diun:/data"
          "${configFile}:/diun.yml"
          "${config.age.secrets.ssmtpPass.path}:/smtppass"
        ];
        # DIUN_NOTIF_MAIL_USERNAME comes from the smtpUser env file (shared
        # with the msmtp activation script); keeps the email out of the
        # /nix/store copy of diun-config.yml.
        environmentFiles = [ config.age.secrets.smtpUser.path ];
        environment = {
          TZ = config.time.timeZone;
          PUID = toString config.ids.uids.${config.mine.storageUser};
          PGID = toString config.ids.gids.${config.mine.storageGroup};
        };
      };
  };
}
