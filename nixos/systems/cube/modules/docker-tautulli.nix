{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.tautulli;
  port = toString cfg.port;
in {
  systemd.tmpfiles.rules = [
    "d ${config.mine.storagePath}/tautulli 0755 - - - -"
  ];

  virtualisation.oci-containers.containers.tautulli = {
    image = "lscr.io/linuxserver/tautulli";
    ports = ["${port}:8181"];
    volumes = [
      "${config.mine.persistPath}/tautulli:/config"
    ];
    extraOptions = ["--network=host"];
    environment = {
      PUID = toString config.ids.uids.${config.mine.storageUser};
      PGID = toString config.ids.gids.${config.mine.storageGroup};
    };
  };

  services.nginx.virtualHosts."tautulli.${config.networking.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${port}";
  };
}
