{ config, lib, pkgs, ... }:
let
  cfg = config.services.nginx;
in
{
  options = {
    services.nginx.appendStreamConfig = lib.mkOption {
      type = lib.types.lines;
      description =
        "Configuration lines to be appended to the generated stream block";
    };
  };
  config = {
    services.nginx.enable = true;
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.nginx = {
      appendConfig = ''
        stream {
           ${cfg.appendStreamConfig}
        }
      '';

      virtualHosts.default = {
        default = true;
        extraConfig = "return 444;";
      };

      virtualHosts.${config.mine.domain} = {
        enableACME = true;
        forceSSL = true;
        serverAliases = [
          "www.${config.mine.domain}"
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
}
