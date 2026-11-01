{ config, pkgs, ... }:
let
  appImage = "invoiceninja/invoiceninja-debian:5.13.49@sha256:05efd0913eb0d72d0246ec96d6cb6adf5ac3d3e59b9b91514b9f64b892f21c92";
  # NOTE: Invoice Ninja supports only MySQL/MariaDB. 8.4 is the MySQL LTS series.
  mysqlImage = "mysql:8.4.11";
  nginxImage = "nginx:1.30.4-alpine3.24";

  hostname = "billing.vpn.denys.me";
  dbName = "invoiceninja";
  dbUser = "invoiceninja";
  dbHost = "invoiceninja-mysql";

  # NOTE: Pinned for TRUSTED_PROXIES and the nginx resolver. 10.89.0.0/24 and 10.89.1.0/24 are taken.
  appSubnet = "10.89.2.0/24";
  dbSubnet = "10.89.3.0/24";

  podCfg = config.home-manager.users.pod.virtualisation.quadlet;
  routes = pkgs.writeText "invoiceninja-routes.yml" (builtins.toJSON (import ./routes.nix));

  envFile = config.age.secrets.invoiceninjaEnv.path;
  sesEnvFile = config.age.secrets.invoiceninjaSesEnv.path;
  rootPassFile = config.age.secrets.mysqlRootPass.path;

  # NOTE: `podman exec` uses the MySQL local socket, so root needs no network grant.
  initScript = pkgs.writeShellScript "invoiceninja-initdb" ''
    set -euo pipefail

    MYSQL_PWD="$(${pkgs.coreutils}/bin/cat ${rootPassFile})"
    export MYSQL_PWD

    password_lines="$(${pkgs.gnugrep}/bin/grep -c '^DB_PASSWORD=' ${envFile} || true)"
    if [ "$password_lines" -ne 1 ]; then
      echo "invoiceninja-initdb: DB_PASSWORD must occur exactly once" >&2
      exit 1
    fi
    USER_PASSWORD="$(${pkgs.gnused}/bin/sed -n 's/^DB_PASSWORD=//p' ${envFile})"
    if [ -z "$USER_PASSWORD" ]; then
      echo "invoiceninja-initdb: DB_PASSWORD is empty" >&2
      exit 1
    fi

    # The environment-file representation cannot safely contain newlines.
    # Escape the two MySQL string-literal metacharacters before interpolation.
    case "$USER_PASSWORD" in
      *$'\n'*|*$'\r'*)
        echo "invoiceninja-initdb: DB_PASSWORD contains a newline" >&2
        exit 1
        ;;
    esac
    USER_PASSWORD_SQL="$(${pkgs.coreutils}/bin/printf '%s' "$USER_PASSWORD" | ${pkgs.gnused}/bin/sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"

    # `podman exec` reaches the socket in the database namespace. Wait for a
    # real SQL statement rather than relying only on mysqladmin's TCP ping.
    echo "Waiting for mysql..." >&2
    until ${pkgs.podman}/bin/podman exec -e MYSQL_PWD ${dbHost} \
      mysql --protocol=socket --user root --silent --execute 'SELECT 1' >/dev/null 2>&1; do
      ${pkgs.coreutils}/bin/sleep 2
    done

    # utf8mb4 so invoice line items accept the full Unicode range (emoji,
    # CJK) rather than the 3-byte-only legacy utf8.
    ${pkgs.podman}/bin/podman exec -i -e MYSQL_PWD ${dbHost} \
      mysql --protocol=socket --user root <<EOSQL
      CREATE DATABASE IF NOT EXISTS ${dbName}
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
      CREATE USER IF NOT EXISTS '${dbUser}'@'%' IDENTIFIED BY '$USER_PASSWORD_SQL';
      ALTER USER '${dbUser}'@'%' IDENTIFIED BY '$USER_PASSWORD_SQL';
      GRANT ALL PRIVILEGES ON ${dbName}.* TO '${dbUser}'@'%';
      FLUSH PRIVILEGES;
    EOSQL
  '';

  # NOTE: Derived from upstream debian/nginx/laravel.conf. Security headers are set on the traefik router only.
  nginxConf = pkgs.writeText "invoiceninja-nginx.conf" ''
    server {
      listen 80 default_server;
      server_name _;
      root /var/www/html/public;
      index index.php;
      charset utf-8;

      # Rootless containers can receive a new address after restart. Resolve
      # the FastCGI peer through this network's Podman DNS rather than caching
      # the startup address until nginx itself restarts.
      resolver 10.89.2.1 valid=10s ipv6=off;
      set $invoiceninja_upstream invoiceninja-app:9000;

      # Matches upload_max_filesize/post_max_size in the image's php.ini.
      # nginx's 1m default would reject valid expense-receipt uploads.
      client_max_body_size 10m;

      location / {
        try_files $uri $uri/ /index.php?$query_string;
      }

      location = /favicon.ico { access_log off; log_not_found off; }
      location = /robots.txt  { access_log off; log_not_found off; }

      # NOTE: index.php is the sole front controller. Never execute uploaded PHP.
      location ~ \.php(?:/|$) {
        return 404;
      }
      location ~ /\.(?!well-known).* {
        deny all;
      }

      location = /index.php {
        internal;
        try_files $uri =404;
        fastcgi_pass $invoiceninja_upstream;
        # $realpath_root, not $document_root: `public` is a volume that init.sh
        # repopulates, so resolve symlinks the way upstream does.
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        # This nginx is reachable only from Traefik's HTTPS router. Pin the
        # transport metadata instead of trusting client-supplied headers;
        # otherwise REQUIRE_HTTPS redirects every request back to itself.
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
        fastcgi_param HTTP_X_FORWARDED_HOST $host;
        fastcgi_param HTTP_X_FORWARDED_PORT 443;
        fastcgi_param HTTP_X_FORWARDED_FOR $http_x_forwarded_for;
        # Chromium-backed PDF rendering and large reports routinely exceed the
        # 60s default on this ARM host.
        fastcgi_read_timeout 300s;
      }
    }
  '';
in
{
  home-manager.users.pod.virtualisation.quadlet = {
    # NOTE: Not `internal`: the app needs egress for SES, exchange rates, and payment gateways.
    networks.invoiceninja.networkConfig = {
      name = "invoiceninja";
      subnets = [ appSubnet ];
    };
    networks.invoiceninja-db.networkConfig = {
      name = "invoiceninja-db";
      subnets = [ dbSubnet ];
      internal = true;
    };

    # NOTE: init.sh rebuilds public/ on each boot. storage/ is not regenerable; see chunkymonkey/backups.nix.
    volumes.invoiceninja-public.volumeConfig = { };
    volumes.invoiceninja-storage.volumeConfig = { };
    volumes.invoiceninja-mysql.volumeConfig = { };

    containers.invoiceninja-mysql = {
      autoStart = true;
      containerConfig = {
        image = mysqlImage;
        volumes = [
          "${podCfg.volumes.invoiceninja-mysql.ref}:/var/lib/mysql"
          "${rootPassFile}:${rootPassFile}:ro"
        ];
        environments = {
          MYSQL_ROOT_PASSWORD_FILE = rootPassFile;
          # NOTE: Applied only on first datadir init.
          MYSQL_ROOT_HOST = "localhost";
        };
        networks = [ podCfg.networks.invoiceninja-db.ref ];

        # NOTE: TCP, not socket: the entrypoint's temporary init server is socket-only.
        healthCmd = "mysqladmin ping -h 127.0.0.1 --silent";
        healthStartPeriod = "60s";
        healthInterval = "10s";
        healthRetries = 12;
        notify = "healthy";
      };
      serviceConfig = {
        Restart = "on-failure";
        MemoryHigh = "1500M";
        MemoryMax = "2G";
      };
    };

    containers.invoiceninja-app = {
      autoStart = true;
      unitConfig = {
        After = [
          "invoiceninja-initdb.service"
          podCfg.containers.invoiceninja-mysql.ref
        ];
        Requires = [
          "invoiceninja-initdb.service"
          podCfg.containers.invoiceninja-mysql.ref
        ];
        # NOTE: Home Manager can split an app restart into stop/start jobs; restart nginx after PartOf= stops it.
        Wants = [ podCfg.containers.invoiceninja-nginx.ref ];
      };
      containerConfig = {
        image = appImage;
        environmentFiles = [
          envFile
          sesEnvFile
        ];
        environments = {
          APP_URL = "https://${hostname}";
          REACT_URL = "https://${hostname}";
          SESSION_DOMAIN = "null";
          SESSION_SECURE_COOKIE = "true";
          APP_ENV = "production";
          APP_DEBUG = "false";
          APP_TIMEZONE = "America/Toronto";
          REQUIRE_HTTPS = "true";
          # NOTE: nginx subnet only, not "*": a compromised neighbour cannot spoof X-Forwarded-*.
          TRUSTED_PROXIES = appSubnet;
          # NOTE: The image ships chromium on arm64.
          PDF_GENERATOR = "snappdf";
          # NOTE: database/file drivers avoid redis; the image's supervisord runs the queue worker.
          QUEUE_CONNECTION = "database";
          CACHE_DRIVER = "file";
          SESSION_DRIVER = "file";
          DB_CONNECTION = "mysql";
          DB_HOST = dbHost;
          DB_PORT = "3306";
          DB_DATABASE = dbName;
          DB_USERNAME = dbUser;
        };
        volumes = [
          "${podCfg.volumes.invoiceninja-public.ref}:/var/www/html/public"
          "${podCfg.volumes.invoiceninja-storage.ref}:/var/www/html/storage"
        ];
        networks = [
          podCfg.networks.invoiceninja-db.ref
          podCfg.networks.invoiceninja.ref
        ];
        # NOTE: No proxy network: the app speaks FastCGI only; traefik routes to nginx.

        # NOTE: The published tag lacks the upstream Dockerfile HEALTHCHECK.
        healthCmd = "REMOTE_ADDR=127.0.0.1 REQUEST_URI=/health REQUEST_METHOD=GET SCRIPT_FILENAME=/var/www/html/public/index.php cgi-fcgi -bind -connect 127.0.0.1:9000 | grep '{\"status\":\"ok\",\"message\":\"API is healthy\"}'";
        healthStartPeriod = "100s";
        healthInterval = "15s";
        healthRetries = 20;
        notify = "healthy";
      };
      serviceConfig = {
        Restart = "on-failure";
        # NOTE: init.sh runs migrations before supervisord; first boot exceeds the default start timeout.
        TimeoutStartSec = "15m";
        # NOTE: Sized for php-fpm, scheduler, 2 queue workers, and chromium.
        MemoryHigh = "2G";
        MemoryMax = "3G";
      };
    };

    containers.traefik.containerConfig.volumes = [
      "${routes}:/etc/traefik/dynamic/invoiceninja.yml:ro"
    ];

    containers.invoiceninja-nginx = {
      autoStart = true;
      unitConfig = {
        After = [ podCfg.containers.invoiceninja-app.ref ];
        Requires = [ podCfg.containers.invoiceninja-app.ref ];
        # NOTE: The app's Wants= restarts nginx. Podman DNS handles app self-restarts.
        PartOf = [ podCfg.containers.invoiceninja-app.ref ];
      };
      containerConfig = {
        image = nginxImage;
        volumes = [
          "${nginxConf}:/etc/nginx/conf.d/default.conf:ro"
          "${podCfg.volumes.invoiceninja-public.ref}:/var/www/html/public:ro"
          "${podCfg.volumes.invoiceninja-storage.ref}:/var/www/html/storage:ro"
        ];
        networks = [
          podCfg.networks.invoiceninja.ref
          podCfg.networks.proxy.ref
        ];
      };
      serviceConfig = {
        Restart = "on-failure";
        MemoryHigh = "128M";
        MemoryMax = "192M";
      };
    };
  };

  # NOTE: RemainAfterExit keeps the app dependency met. Restart this unit to rotate DB credentials.
  home-manager.users.pod.systemd.user.services.invoiceninja-initdb = {
    Unit = {
      Description = "Provision the Invoice Ninja MySQL database";
      After = [ podCfg.containers.invoiceninja-mysql.ref ];
      Requires = [ podCfg.containers.invoiceninja-mysql.ref ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5m";
      MemoryMax = "256M";
      ExecStart = initScript;
    };
  };

  # NOTE: restic backupPrepareCommand also runs this dump. The timer is a fallback.
  home-manager.users.pod.systemd.user.timers."mysql-dump@${dbName}" = {
    Unit.Description = "Daily ${dbName} MySQL dump";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
