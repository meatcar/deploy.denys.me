{
  config,
  lib,
  ...
}: let
  cfg = config.services.freshrss;
  port = toString cfg.port;
in {
  options = {
    services.freshrss = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "freshrss port to listen to locally";
        default = 8422;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mine.storagePath}/freshrss 0755 - - - -"
    ];

    systemd.services."init-postgres-user-db@freshrss" = {
      wantedBy = ["machines.target"];
      overrideStrategy = "asDropin";

      serviceConfig.LoadCredential = [
        "userPgPass:${config.age.secrets.freshrssPgPass.path}"
      ];
    };

    virtualisation.oci-containers.containers.freshrss = {
      image = "lscr.io/linuxserver/freshrss:latest ";
      ports = ["${port}:80"];
      volumes = [
        "${config.mine.persistPath}/freshrss:/config"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
      };
      extraOptions = ["--network=postgres"];
    };

    services.nginx.virtualHosts."rss.${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:${port}";
    };
  };
}
