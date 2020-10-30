{ config, pkgs, lib, ... }:
let
  cfg = config.mine.nodered;
in
{
  options.mine.nodered = with lib; {
    enable = mkEnableOption "Node-RED config";

    port = mkOption {
      type = types.int;
      default = 1880;
      description = "Node-RED port";
    };

    domain = mkOption {
      type = types.str;
      default = "nodered.${config.mine.domain}";
      description = "Node-RED domain";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /persist/nodered 0700 1000 1000 -"
    ];

    docker-containers.nodered = {
      image = "nodered/node-red";
      ports = [ "1880:${toString cfg.port}" ];
      volumes = [
        "/persist/nodered:/data"
      ];
    };

    services.nginx = {
      virtualHosts."${cfg.domain}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString cfg.port}";
          proxyWebsockets = true;
          # extraConfig = ''
          #   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          # '';
        };
      };
      # appendStreamConfig = ''
      #   upstream nodered {
      #     server localhost:${cfg.port};
      #   }
      #   server {
      #     listen ${toString cfg.port} ssl;
      #     listen [::]:${toString cfg.port} ssl;
      #     ssl_certificate /var/lib/acme/${cfg.domain}/fullchain.pem;
      #     ssl_certificate_key /var/lib/acme/${cfg.domain}/key.pem;
      #     ssl_trusted_certificate /var/lib/acme/${cfg.domain}/full.pem;
      #     proxy_pass znc-irc;
      #   }
      # '';
    };
  };
}
