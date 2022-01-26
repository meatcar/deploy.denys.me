{ config, lib, pkgs, ... }:
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
          default https_default;
        }

        upstream https_default {
          server localhost:${toString port};
        }

        server {
          listen 443;
          proxy_pass $name;
          ssl_preread on;
        }
      '';

      virtualHosts = {
        default = {
          default = true;
          extraConfig = "return 444;";
        };

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
          root = builtins.fetchGit {
            url = "https://github.com/meatcar/denys.me";
            ref = "master";
            rev = "dffcfe2441651193161901a4b340abb81a8d93a5";
          };
          extraConfig = "index index.html;";
        };

        };
      };
    };
  };
}
