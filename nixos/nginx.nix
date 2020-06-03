{ config, lib, pkgs, ... }:
let cfg = config.services.nginx;
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

    services.nginx.appendConfig = ''
      stream {
         ${cfg.appendStreamConfig}
      }
    '';
  };
}
