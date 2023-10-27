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

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    virtualisation.oci-containers.containers.plex = {
      image = "plexinc/pms-docker";
      ports = [ "${port}:32400" ];
      volumes = [
        "${config.persistPath}/plex:/config"
        "/data:/data"
      ];
      extraOptions = [
        "--network=host"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.storageUser};
        PGID = toString config.ids.gids.${config.storageGroup};
      };
    };

    services.nginx = {
      clientMaxBodySize = "100M";
      virtualHosts."plex.${config.networking.fqdn}" = {
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
