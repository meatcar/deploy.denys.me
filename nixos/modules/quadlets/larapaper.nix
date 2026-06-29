# LaraPaper BYOS TRMNL server (https://github.com/usetrmnl/larapaper).
# Runs rootless under the pod user via Podman Quadlet.
# larapaper-initdb: init container (RemainAfterExit) that provisions the
#   larapaper role + DB in the shared postgres instance before larapaper starts.
# larapaper: the app container on the postgres + proxy quadlet networks.
# Secrets required in agenix.nix (owner=pod): larapaperEnv, larapaperPgPass.
{ config, pkgs, ... }:
let
  image = "ghcr.io/usetrmnl/larapaper:0.37.1";
  dataDir = "${config.mine.persistPath}/larapaper";

  # Provisioning script: creates the larapaper pg role + db idempotently.
  # Runs inside a postgres:alpine init container on the postgres network.
  # Notes:
  #   - \$do\$ escapes the $do$ dollar-quoting so bash heredoc doesn't expand $do
  #   - $USER_PASSWORD IS expanded by the shell (that's intentional)
  #   - "UNICODE" uses SQL identifier quoting to avoid Nix ''..'' string issues
  initScript = pkgs.writeShellScript "larapaper-initdb" ''
    set -euo pipefail
    export PGPASSWORD
    PGPASSWORD=$(cat /run/secrets/postgresPass)
    USER_PASSWORD=$(cat /run/secrets/larapaperPgPass)

    echo "Waiting for postgres..." >&2
    until psql --host postgres --username postgres -c '\q' 2>/dev/null; do
      sleep 2
    done

    psql --host postgres --username postgres <<EOSQL
      DO \$do\$
      BEGIN
        IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'larapaper') THEN
          RAISE NOTICE 'Role "larapaper" already exists. Skipping.';
        ELSE
          CREATE ROLE larapaper LOGIN PASSWORD '$USER_PASSWORD';
        END IF;
      END
      \$do\$;

      SELECT 'CREATE DATABASE larapaper ENCODING "UNICODE"'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'larapaper')\gexec

      ALTER DATABASE larapaper OWNER TO larapaper;
      GRANT ALL PRIVILEGES ON DATABASE larapaper TO larapaper;
    EOSQL
  '';

  podCfg = config.home-manager.users.pod.virtualisation.quadlet;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 pod pod - -"
  ];

  home-manager.users.pod.virtualisation.quadlet = {
    # Named volume for generated screen images. Starts empty on first deploy;
    # larapaper regenerates screens periodically so this is acceptable.
    volumes.larapaper-storage.volumeConfig = { };

    # Init container: provisions the larapaper role+DB.
    # RemainAfterExit=yes keeps the service "active" after the script exits so
    # larapaper.service's Requires= is satisfied. Restart=no prevents re-runs.
    # Type=oneshot is intentionally absent: podman quadlet uses Type=notify and
    # adding Type=oneshot conflicts with the generated NotifyAccess=all setting,
    # producing a BadUnitSetting error at load time.
    containers.larapaper-initdb = {
      autoStart = false; # pulled in on-demand by larapaper.service
      serviceConfig = {
        RemainAfterExit = "yes";
        Restart = "no";
      };
      unitConfig = {
        After = [ podCfg.containers.postgres.ref ];
        Requires = [ podCfg.containers.postgres.ref ];
      };
      containerConfig = {
        image = "postgres:18.4-alpine"; # provides psql
        entrypoint = "sh";
        exec = "${initScript}";
        volumes = [
          "${config.age.secrets.postgresPass.path}:/run/secrets/postgresPass:ro"
          "${config.age.secrets.larapaperPgPass.path}:/run/secrets/larapaperPgPass:ro"
          # Mount the script from the Nix store into the container at its own path.
          "${initScript}:${initScript}:ro"
        ];
        networks = [ podCfg.networks.postgres.ref ];
      };
    };

    containers.larapaper = {
      autoStart = true;
      unitConfig = {
        After = [
          podCfg.containers.larapaper-initdb.ref
          podCfg.containers.postgres.ref
        ];
        Requires = [
          podCfg.containers.larapaper-initdb.ref
          podCfg.containers.postgres.ref
        ];
      };
      containerConfig = {
        inherit image;
        environmentFiles = [ config.age.secrets.larapaperEnv.path ]; # APP_KEY, DB_PASSWORD
        environments = {
          APP_URL = "https://trmnl.denys.me";
          APP_TIMEZONE = "America/Toronto";
          FORCE_HTTPS = "true"; # Traefik terminates TLS
          TRUSTED_PROXIES = "*"; # trust the proxy network for correct scheme/host
          DB_CONNECTION = "pgsql";
          DB_HOST = "postgres"; # resolved via podman DNS on the postgres network
          DB_PORT = "5432";
          DB_DATABASE = "larapaper";
          DB_USERNAME = "larapaper";
          PHP_OPCACHE_ENABLE = "1";
          APP_ENV = "production";
          APP_DEBUG = "false";
          TRMNL_PROXY_REFRESH_MINUTES = "15";
          REGISTRATION_ENABLED = "0";
        };
        volumes = [
          "${podCfg.volumes.larapaper-storage.ref}:/var/www/html/storage/app/public/images/generated"
        ];
        networks = [
          podCfg.networks.postgres.ref
          podCfg.networks.proxy.ref
        ];
        # Traefik discovers this container via the pod user's podman socket.
        labels = {
          "traefik.enable" = "true";
          "traefik.docker.network" = "proxy";
          "traefik.http.routers.larapaper.rule" = "Host(`trmnl.denys.me`)";
          "traefik.http.routers.larapaper.entrypoints" = "websecure";
          "traefik.http.routers.larapaper.tls.certresolver" = "le";
          "traefik.http.services.larapaper.loadbalancer.server.port" = "8080";
        };
      };
      serviceConfig.Restart = "on-failure";
    };
  };

  # Instantiate the pg-dump timer for larapaper (template defined in pg-dump.nix).
  home-manager.users.pod.systemd.user.timers."pg-dump@larapaper" = {
    Unit.Description = "Daily larapaper PostgreSQL dump";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = true; # catch up missed runs after downtime
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
