{ config, pkgs, lib, ... }:
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
      "d ${config.persistPath}/diun 0750 - - - -"
    ];
    virtualisation.oci-containers.containers.diun =
      let
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
              host: smtp.fastmail.com
              port: 565
              ssl: true
              localName: ${config.fqdn}
              username: ${config.smtp.user}
              passwordFile: /smtppass
              from: diun.cube@denys.me
              to: admin.cube@denys.me
        '';
      in
      {
        image = "crazymax/diun";
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
          "${config.persistPath}/diun:/data"
          "${configFile}:/diun.yml"
          "${config.sops.secrets.ssmtpPass.path}:/smtppass"
        ];
        environment = {
          TZ = config.time.timeZone;
          PUID = toString config.ids.uids.${config.storageUser};
          PGID = toString config.ids.gids.${config.storageGroup};
        };
      };
  };
}
