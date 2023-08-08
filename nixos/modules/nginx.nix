{ config, lib, pkgs, specialArgs, ... }:
let
  cfg = config.services.nginx;
  port = config.mine.internalSslPort;
in
{
  options.mine.internalSslPort = lib.mkOption {
    type = lib.types.int;
    default = 44443;
    description = "Port to expose SSL servers on internally";
  };
  config = {
    services.nginx.enable = true;
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.nginx = {
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      statusPage = true;

      streamConfig = ''
        map $ssl_preread_server_name $name {
          cube.${config.mine.domain} cube;
          ~.+.cube.${config.mine.domain} cube;
          huddle.win cube;
          ~.+.huddle.win cube;
          default https_default;
        }

        upstream https_default {
          server localhost:${toString port};
        }

        upstream cube {
          server 10.100.0.4:443;
        }

        server {
          listen 443;
          proxy_pass $name;
          ssl_preread on;
        }
      '';

      virtualHosts = {
        ${config.mine.domain} = {
          enableACME = true;
          forceSSL = true;
          serverAliases = [
            "www.${config.mine.domain}"
          ];
          listen = [
            { addr = "0.0.0.0"; port = 80; }
            { addr = "127.0.0.1"; inherit port; ssl = true; }
          ];
          root = specialArgs.inputs.website;
          extraConfig = "index index.html;";
        };

        "cube.${config.mine.domain}" = {
          # http only, mostly for acme/letsencrypt challenges
          serverAliases = [ "*.cube.${config.mine.domain}" ];
          locations."/".proxyPass = "http://10.100.0.4";
        };
        "huddle.win" = {
          # http only, mostly for acme/letsencrypt challenges
          serverAliases = [ "*.huddle.win" ];
          locations."/".proxyPass = "http://10.100.0.4";
        };
      };

    };
  };
}
