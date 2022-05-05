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
      "d /persist/nodered 0700 1000 100 -"
    ];

    virtualisation.oci-containers.containers.nodered = {
      image = "nodered/node-red";
      ports = [ "1880:${toString cfg.port}" ];
      volumes = [
        "/persist/nodered:/data"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      extraOptions = [ "--group-add=${toString config.users.groups.docker.gid}" ];
    };

    services.nginx = {
      virtualHosts."${cfg.domain}" = {
        enableACME = true;
        forceSSL = true;
        listen = [
          { addr = "0.0.0.0"; port = 80; }
          { addr = "127.0.0.1"; port = config.mine.internalSslPort; ssl = true; }
        ];
        locations."/" = {
          proxyPass = "http://localhost:${toString cfg.port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
