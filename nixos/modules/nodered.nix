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
      default = "nodered.${config.networking.domain}";
      description = "Node-RED domain";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /persist/nodered 0700 1000 100 -"
    ];

    systemd.services.init-docker-network-nodered = {
      description = "Create the docker network nodered for nodered.";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig.Type = "oneshot";
      script =
        let
          docker = "${config.virtualisation.docker.package}/bin/docker";
          network = "nodered";
        in
        ''
          check=$(${docker} network ls | grep "${network}" || true)
          if [ -z "$check" ]; then
            ${docker} network create "${network}"
          else
            echo "docker network '${network}' already exists"
          fi
        '';
    };

    virtualisation.oci-containers.containers.nodered = {
      image = "nodered/node-red";
      ports = [ "1880:${toString cfg.port}" ];
      volumes = [
        "/persist/nodered:/data"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      extraOptions = [
        "--group-add=${toString config.users.groups.docker.gid}"
        "--network=nodered"
      ];
    };

    services.nginx = {
      virtualHosts."${cfg.domain}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString cfg.port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
