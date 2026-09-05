{
  config,
  lib,
  pkgs,
  ...
}:
let
  deployment = builtins.fromJSON (builtins.readFile config.mine.cliProxyApi.deploymentFile);
  dataDir = deployment.state_directory;
  user = deployment.service_user;
  quadlet = config.home-manager.users.${user}.virtualisation.quadlet;
  packages = import ./images.nix { inherit pkgs; };
  operations = import ../../../../packages/cli-proxy-api/package.nix { inherit pkgs; };
  managerImage = "docker.io/seakee/cpa-manager-plus:v1.12.13@sha256:ed14d58c58e02e4fa3c4343de4388f8521bdff6411ff98f3f27e0c8adead326f";
  admin = pkgs.writeShellApplication {
    name = "cli-proxy-api-admin";
    text = ''
      exec ${operations}/bin/cli-proxy-api-admin \
        --state ${lib.escapeShellArg dataDir} --image ${managerImage} \
        --service cpa-manager-plus \
        --url ${lib.escapeShellArg "https://${deployment.management_host}:9443"} \
        --connect-to ${lib.escapeShellArg "${deployment.management_host}:9443:127.0.0.1:9443"} "$@"
    '';
  };
  routes = pkgs.writeText "cli-proxy-api-routes.yml" (
    builtins.toJSON (
      import ./routes.nix {
        publicHost = deployment.public_host;
        managementHost = deployment.management_host;
      }
    )
  );
  settings = pkgs.writeText "cli-proxy-api-settings.json" (
    builtins.toJSON (
      import ./settings.nix {
        publicHost = deployment.public_host;
        bridgeVersion = packages.bridge.version;
      }
    )
  );
in
{
  imports = [ ./firewall.nix ];

  options.mine.cliProxyApi.deploymentFile = lib.mkOption {
    type = lib.types.path;
    description = "Non-secret CLIProxyAPI deployment profile.";
  };
  options.mine.cliProxyApi.backupFile = lib.mkOption {
    type = lib.types.str;
    description = "Absolute archive path outside the CLIProxyAPI state directory.";
  };

  config = {
    environment.systemPackages = [ admin ];

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0700 ${user} ${config.users.users.${user}.group} - -"
      "d ${dataDir}/auth 0700 ${user} ${config.users.users.${user}.group} - -"
      "d ${builtins.dirOf config.mine.cliProxyApi.backupFile} 0750 ${user} ${
        config.users.users.${user}.group
      } - -"
    ];

    home-manager.users.${user} = {
      systemd.user.services.cli-proxy-api.Service.ExecStartPre =
        "${operations}/bin/cli-proxy-api-initialize ${dataDir}/config.yaml --settings ${settings}";
      systemd.user.services.cpa-manager-plus.Service.ExecStartPre =
        "${admin}/bin/cli-proxy-api-admin recover";
      systemd.user.services.cli-proxy-api-admin-rotate = {
        Unit.Description = "Reconcile the staged Manager Plus admin credential";
        Service = {
          Type = "oneshot";
          ExecStart = "${admin}/bin/cli-proxy-api-admin reconcile";
          TimeoutStartSec = 300;
          UMask = "0077";
        };
      };
      systemd.user.services.cli-proxy-api-backup = {
        Unit.Description = "Snapshot CLIProxyAPI state and Manager Plus database";
        Service = {
          Type = "oneshot";
          ExecStart = lib.escapeShellArgs [
            "${operations}/bin/cli-proxy-api-backup"
            dataDir
            config.mine.cliProxyApi.backupFile
          ];
          TimeoutStartSec = "5m";
          UMask = "0077";
        };
      };

      virtualisation.quadlet = {
        images.cli-proxy-api.imageConfig = {
          image = "docker-archive:${packages.image}";
          tag = "localhost/cli-proxy-api:${packages.api.version}-pi-${packages.bridge.version}";
        };
        images.cpa-manager-plus.imageConfig.image = managerImage;
        networks.cli-proxy-api.networkConfig.name = "cli-proxy-api";
        containers.traefik.containerConfig = {
          networks = [ quadlet.networks.cli-proxy-api.ref ];
          volumes = [ "${routes}:/etc/traefik/dynamic/cli-proxy-api.yml:ro" ];
        };
        containers.cli-proxy-api = {
          autoStart = true;
          containerConfig = {
            image = quadlet.images.cli-proxy-api.ref;
            name = "cli-proxy-api";
            exec = "-config /CLIProxyAPI/state/config.yaml";
            networks = [ quadlet.networks.cli-proxy-api.ref ];
            volumes = [ "${dataDir}:/CLIProxyAPI/state" ];
            dropCapabilities = [ "all" ];
            noNewPrivileges = true;
            readOnly = true;
            tmpfses = [ "/tmp" ];
          };
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 5;
            MemoryHigh = "512M";
            MemoryMax = "1G";
            UMask = "0077";
          };
        };
        containers.cpa-manager-plus = {
          autoStart = true;
          unitConfig = {
            After = [ quadlet.containers.cli-proxy-api.ref ];
            Wants = [ quadlet.containers.cli-proxy-api.ref ];
          };
          containerConfig = {
            image = quadlet.images.cpa-manager-plus.ref;
            name = "cpa-manager-plus";
            networks = [ quadlet.networks.cli-proxy-api.ref ];
            volumes = [
              "${dataDir}/manager:/data"
              "${dataDir}/management-key:/run/secrets/cpa-management-key:ro"
            ];
            environments = {
              HTTP_ADDR = "0.0.0.0:18317";
              USAGE_DATA_DIR = "/data";
              USAGE_DB_PATH = "/data/usage.sqlite";
              CPA_MANAGER_DATA_KEY_PATH = "/data/data.key";
              CPA_MANAGER_ADMIN_KEY_FILE = "/data/admin-key";
              CPA_UPSTREAM_URL = "http://cli-proxy-api:8317";
              CPA_MANAGEMENT_KEY_FILE = "/run/secrets/cpa-management-key";
              USAGE_COLLECTOR_MODE = "auto";
            };
            dropCapabilities = [ "all" ];
            noNewPrivileges = true;
            readOnly = true;
            tmpfses = [ "/tmp" ];
          };
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 5;
            MemoryHigh = "256M";
            MemoryMax = "512M";
            UMask = "0077";
          };
        };
      };
    };
  };
}
