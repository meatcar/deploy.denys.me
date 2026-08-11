# Invoice Ninja (https://github.com/invoiceninja/dockerfiles, debian branch).
# Runs rootless under the pod user via Podman Quadlet.
#
# Four containers, all on networks private to this app:
#   invoiceninja-mysql   dedicated MySQL 8.4 LTS. Not the shared postgres
#                        instance: Invoice Ninja only supports MySQL/MariaDB.
#   invoiceninja-initdb  idempotent init container. Waits for MySQL to accept
#                        real queries, then provisions the app DB role from the
#                        same DB_PASSWORD the app itself uses.
#   invoiceninja-app     upstream image: php-fpm + Laravel scheduler + 2 queue
#                        workers under supervisord. Speaks FastCGI only.
#   invoiceninja-nginx   serves the public/storage volumes and fastcgi_passes
#                        to the app. The only container on `proxy`, because
#                        traefik cannot speak FastCGI.
#
# Secrets required in agenix.nix (owner=pod): invoiceninjaEnv,
# invoiceninjaSesEnv, mysqlRootPass.
{ config, pkgs, ... }:
let
  # Pinned by exact patch, matching the traefik/postgres convention in this
  # repo. All three verified to publish native linux/arm64 manifests.
  appImage = "invoiceninja/invoiceninja-debian:5.13.29";
  mysqlImage = "mysql:8.4.11"; # 8.4 is the current MySQL LTS series
  nginxImage = "nginx:1.30.4-alpine3.24"; # nginx stable branch

  hostname = "billing.denys.me";
  dbName = "invoiceninja";
  dbUser = "invoiceninja";
  # Container name doubles as its DNS name on the podman network.
  dbHost = "invoiceninja-mysql";

  # Pinned subnets so TRUSTED_PROXIES can name the proxy hop exactly instead of
  # the "*" wildcard used elsewhere. 10.89.0.0/24 and 10.89.1.0/24 are already
  # taken by the shared `proxy` and `postgres` networks.
  appSubnet = "10.89.2.0/24";
  dbSubnet = "10.89.3.0/24";

  podCfg = config.home-manager.users.pod.virtualisation.quadlet;

  envFile = config.age.secrets.invoiceninjaEnv.path;
  sesEnvFile = config.age.secrets.invoiceninjaSesEnv.path;
  rootPassFile = config.age.secrets.mysqlRootPass.path;

  # This is a host user service rather than a Quadlet container. `podman exec`
  # uses MySQL's local socket, so root never needs a network-accessible grant.
  # DB_PASSWORD is sourced from the app's own env file, so there is no second
  # copy of the password to keep in sync.
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

  # 5.13.29 has several SNS boundary defects: confirmation signatures are not
  # checked, verifier exceptions fall back to structural validation, the signed
  # field list handles notifications only, normal confirmation tokens can exceed
  # 200 bytes, and ca-central-1 is missing from the certificate hosts. It also
  # retries valid host-alert feedback forever. Keep this exact-version patch
  # narrow and fail the build if an upstream fragment changes under us.
  snsControllerSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/invoiceninja/invoiceninja/v5.13.29/app/Http/Controllers/SNSController.php";
    hash = "sha256-raCsRqQRRDNJYwgdiC8M7fABAKakVvCXRbGBNN9EYf0=";
  };
  snsController =
    pkgs.runCommand "invoiceninja-sns-controller.php" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${snsControllerSource} "$out"
        chmod u+w "$out"
        python - "$out" <<'PY'
        from pathlib import Path
        import sys

        path = Path(sys.argv[1])
        source = path.read_text()
        regions = """        // Check if it's an AWS domain
                $validDomains = [
                    'sns.us-east-1.amazonaws.com',
                    'sns.us-east-2.amazonaws.com',
                    'sns.us-west-1.amazonaws.com',
                    'sns.us-west-2.amazonaws.com',
                    'sns.eu-west-1.amazonaws.com',
                    'sns.eu-central-1.amazonaws.com',
                    'sns.ap-southeast-1.amazonaws.com',
                    'sns.ap-southeast-2.amazonaws.com',
                    'sns.ap-northeast-1.amazonaws.com',
                    'sns.sa-east-1.amazonaws.com',
                ];

                return in_array($parsedUrl['host'], $validDomains);
        """
        regional_host = """        return isset($parsedUrl['scheme']) && $parsedUrl['scheme'] === 'https'
                    && preg_match('/^sns\\.[a-z0-9-]+\\.amazonaws\\.com$/', $parsedUrl['host']) === 1;
        """
        signature_comment = "// Verify SNS signature for security (skip for subscription confirmation)"
        signed_comment = "// Verify every SNS message type before handling it."
        notification_only = "if ($snsMessageType === 'Notification')"
        signed_types = "if (in_array($snsMessageType, ['Notification', 'SubscriptionConfirmation', 'UnsubscribeConfirmation'], true))"
        signature_dispatch = signature_comment + "\n            $snsMessageType = $headers['x-amz-sns-message-type'][0] ?? null;\n\n            " + notification_only
        signed_dispatch = signature_dispatch.replace(signature_comment, signed_comment).replace(notification_only, signed_types)
        notification_fields = """        $fields = [
                    'Message',
                    'MessageId',
                    'Subject',
                    'Timestamp',
                    'TopicArn',
                    'Type',
                ];
        """
        type_fields = """        $fields = match ($snsData['Type'] ?? null) {
                    'Notification' => [
                        'Message',
                        'MessageId',
                        'Subject',
                        'Timestamp',
                        'TopicArn',
                        'Type',
                    ],
                    'SubscriptionConfirmation', 'UnsubscribeConfirmation' => [
                        'Message',
                        'MessageId',
                        'SubscribeURL',
                        'Timestamp',
                        'Token',
                        'TopicArn',
                        'Type',
                    ],
                    default => [],
                };
        """
        fail_open = "return $this->fallbackBasicValidation($request, $payload);"
        token_limit = "if (strlen($token) < 20 || strlen($token) > 200)"
        missing_company = "return response()->json(['error' => 'No company key found'], 400);"
        fragments = (regions, signature_dispatch, notification_fields, fail_open, token_limit, missing_company)
        if any(source.count(fragment) != 1 for fragment in fragments):
            raise SystemExit("upstream SNSController.php changed; refresh the compatibility patch")
        source = source.replace(regions, regional_host)
        source = source.replace(signature_dispatch, signed_dispatch)
        source = source.replace(notification_fields, type_fields)
        source = source.replace(fail_open, "return false;")
        source = source.replace(token_limit, "if (strlen($token) < 20 || strlen($token) > 1024)")
        source = source.replace(missing_company, "return response()->json(['status' => 'ignored'], 200);")
        path.write_text(source)
        PY
      '';

  # Derived from upstream's debian/nginx/laravel.conf. Kept in the Nix store and
  # mounted read-only. Security headers deliberately live on the traefik router
  # instead, so there is exactly one place that sets them.
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

      error_page 404 /index.php;

      location ~ \.php$ {
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

      location ~ /\.(?!well-known).* {
        deny all;
      }
    }
  '';
in
{
  home-manager.users.pod.virtualisation.quadlet = {
    # FastCGI hop, nginx <-> app. Not `internal`: the app needs egress for SES,
    # exchange rates and payment gateways.
    networks.invoiceninja.networkConfig = {
      name = "invoiceninja";
      subnets = [ appSubnet ];
    };
    # internal = no gateway, so MySQL has no route off-host at all. It only ever
    # talks to the app; provisioning enters through its local socket.
    networks.invoiceninja-db.networkConfig = {
      name = "invoiceninja-db";
      subnets = [ dbSubnet ];
      internal = true;
    };

    # public/ is rebuilt from the image by init.sh on every boot, so it is
    # disposable. storage/ holds uploaded documents, logos and generated PDFs:
    # not regenerable, and backed up in chunkymonkey/backups.nix.
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
          # The init service enters through podman exec and the local socket.
          # This is applied only while the MySQL datadir is first initialized.
          MYSQL_ROOT_HOST = "localhost";
        };
        networks = [ podCfg.networks.invoiceninja-db.ref ];
        # No publishPorts: the DB is reachable only over the internal network.

        # The mysql image ships no HEALTHCHECK, so define one and gate the
        # unit on it. Over TCP on purpose: while the entrypoint is building the
        # data directory it runs a temporary socket-only server, and only the
        # real networked server should count as ready.
        # `ping` answers even on access-denied, which is what we want here —
        # proof the server is accepting connections. Credentials are verified
        # for real by invoiceninja-initdb.
        healthCmd = "mysqladmin ping -h 127.0.0.1 --silent";
        healthStartPeriod = "60s";
        healthInterval = "10s";
        healthRetries = 12;
        # Hold the unit in "activating" until the healthcheck passes, so
        # everything ordered After= this genuinely finds a usable database.
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
        # Home Manager may implement a changed app as separate stop/start jobs.
        # Pull nginx back in on the start half after PartOf= stopped it.
        Wants = [ podCfg.containers.invoiceninja-nginx.ref ];
      };
      containerConfig = {
        image = appImage;
        # Bootstrap credentials were removed after the administrator login was
        # verified. Only long-lived application and mail credentials remain.
        environmentFiles = [
          envFile # APP_KEY, DB_PASSWORD
          sesEnvFile # SES API credentials
        ];
        environments = {
          APP_URL = "https://${hostname}";
          APP_ENV = "production";
          APP_DEBUG = "false";
          APP_TIMEZONE = "America/Toronto";
          REQUIRE_HTTPS = "true"; # traefik terminates TLS
          # Only the nginx sidecar's subnet, rather than the "*" used elsewhere
          # in this repo, so a compromised neighbour cannot spoof X-Forwarded-*.
          TRUSTED_PROXIES = appSubnet;
          PDF_GENERATOR = "snappdf"; # image ships chromium on arm64
          # Keeps the dependency surface to MySQL alone; the image's supervisord
          # already runs a queue worker, and the database driver needs no redis.
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
          "${snsController}:/var/www/html/app/Http/Controllers/SNSController.php:ro"
        ];
        networks = [
          podCfg.networks.invoiceninja-db.ref
          podCfg.networks.invoiceninja.ref
        ];
        # No traefik labels and no proxy network: this container speaks FastCGI,
        # not HTTP, so nginx is what gets proxied.

        # The published tag lacks its upstream Dockerfile HEALTHCHECK. Define
        # the same FastCGI /health probe explicitly before using notify=healthy.
        healthCmd = "REMOTE_ADDR=127.0.0.1 REQUEST_URI=/health REQUEST_METHOD=GET SCRIPT_FILENAME=/var/www/html/public/index.php cgi-fcgi -bind -connect 127.0.0.1:9000 | grep '{\"status\":\"ok\",\"message\":\"API is healthy\"}'";
        healthStartPeriod = "100s";
        healthInterval = "15s";
        healthRetries = 20;
        # Gating on it means nginx starts only once php-fpm actually answers.
        notify = "healthy";
      };
      serviceConfig = {
        Restart = "on-failure";
        # init.sh runs migrations before supervisord starts; on a first boot
        # (full schema + seed) that is well beyond the default start timeout.
        TimeoutStartSec = "15m";
        # php-fpm + scheduler + 2 queue workers + chromium for PDF rendering.
        MemoryHigh = "2G";
        MemoryMax = "3G";
      };
    };

    containers.invoiceninja-nginx = {
      autoStart = true;
      unitConfig = {
        After = [ podCfg.containers.invoiceninja-app.ref ];
        Requires = [ podCfg.containers.invoiceninja-app.ref ];
        # Stop nginx whenever the app stops; the app's Wants= then pulls it
        # back in after Home Manager's separate start job. Runtime DNS handles
        # ordinary container self-restarts without requiring this unit restart.
        PartOf = [ podCfg.containers.invoiceninja-app.ref ];
      };
      containerConfig = {
        image = nginxImage;
        volumes = [
          "${nginxConf}:/etc/nginx/conf.d/default.conf:ro"
          # Read-only: only the app writes to these.
          "${podCfg.volumes.invoiceninja-public.ref}:/var/www/html/public:ro"
          "${podCfg.volumes.invoiceninja-storage.ref}:/var/www/html/storage:ro"
        ];
        networks = [
          podCfg.networks.invoiceninja.ref
          podCfg.networks.proxy.ref
        ];
        # Routed by traefik's file provider (see traefik.nix), not by labels:
        # traefik no longer has access to the podman API.
      };
      serviceConfig = {
        Restart = "on-failure";
        MemoryHigh = "128M";
        MemoryMax = "192M";
      };
    };
  };

  # A native user oneshot waits for successful database provisioning before
  # the app may start. RemainAfterExit intentionally keeps its successful state
  # as an app dependency; restart it explicitly when rotating DB credentials.
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

  # Template lives in mysql-dump.nix. restic's backupPrepareCommand also runs
  # this synchronously, so the snapshot always contains a fresh dump; the timer
  # is the standalone safety net.
  home-manager.users.pod.systemd.user.timers."mysql-dump@${dbName}" = {
    Unit.Description = "Daily ${dbName} MySQL dump";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = true; # catch up missed runs after downtime
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
