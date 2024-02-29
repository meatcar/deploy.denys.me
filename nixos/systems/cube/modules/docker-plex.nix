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
      "d ${config.mine.storagePath}/plex 0755 - - - -"
    ];

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    virtualisation.oci-containers.containers.plex = {
      image = "plexinc/pms-docker";
      hostname = config.networking.fqdn;
      ports = [
        "${port}:32400/tcp"
        "8324:8324/tcp"
        "32469:32469/tcp"
        "1900:1900/udp"
        "32410:32410/udp"
        "32412:32412/udp"
        "32413:32413/udp"
        "32414:32414/udp"
      ];
      volumes = [
        "${config.mine.persistPath}/plex:/config"
        "/data/Multimedia:/data/Multimedia"
      ];
      extraOptions = [
        # "--network=host"
        "--device=/dev/dri:/dev/dri" # for transcoding
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
        ADVERTISE_IP = "https://plex.${config.networking.fqdn}:443/";
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
          proxy_set_header X-Plex-Client-Identifier $http_x_plex_client_identifier;
          proxy_set_header X-Plex-Device $http_x_plex_device;
          proxy_set_header X-Plex-Device-Name $http_x_plex_device_name;
          proxy_set_header X-Plex-Platform $http_x_plex_platform;
          proxy_set_header X-Plex-Platform-Version $http_x_plex_platform_version;
          proxy_set_header X-Plex-Product $http_x_plex_product;
          proxy_set_header X-Plex-Token $http_x_plex_token;
          proxy_set_header X-Plex-Version $http_x_plex_version;
          proxy_set_header X-Plex-Nocache $http_x_plex_nocache;
          proxy_set_header X-Plex-Provides $http_x_plex_provides;
          proxy_set_header X-Plex-Device-Vendor $http_x_plex_device_vendor;
          proxy_set_header X-Plex-Model $http_x_plex_model;
        '';
      };
    };
  };
}
