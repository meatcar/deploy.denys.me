{ config, pkgs, lib, ... }:
let
  cfg = config.services.plex;
  port = toString cfg.port;
in
{
  options = {
    services.plex = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "plex port to listen to locally";
        default = 32400;
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.storagePath}/plex 0755 - - - -"
    ];

    virtualisation.oci-containers.containers.plex = {
      image = "lscr.io/linuxserver/plex";
      ports = [ "${port}:32400" ];
      volumes = [
        "${config.persistPath}/plex:/config"
        "/data:/data"
      ];
      extraOptions = [
        "--network=host"
        "--device=/dev/dri:/dev/dri"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx = {
      clientMaxBodySize = "100M";
      virtualHosts."plex.${config.fqdn}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${port}";
          proxyWebsockets = true;
        };
        extraConfig = ''
          proxy_buffering off;
          send_timeout 100m;
        '';
      };
    };
  };
}
