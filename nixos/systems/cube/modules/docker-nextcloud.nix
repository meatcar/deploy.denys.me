{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nextcloud;
  port = toString cfg.port;
  uid = toString config.ids.uids.${config.mine.storageUser};
  gid = toString config.ids.gids.${config.mine.storageGroup};
in {
  options = {
    services.nextcloud = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "nextcloud port to listen to locally";
        default = 8888;
      };
      fqdn = lib.mkOption {
        type = lib.types.str;
        description = "nextcloud domain to listen to";
        default = config.networking.fqdn;
      };
      trusted-domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "nextcloud trusted domains";
        default = [cfg.fqdn];
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mine.persistPath}/nextcloud 0755 ${config.mine.storageUser} ${config.mine.storageGroup} - -"
    ];

    systemd.timers.nextcloud-cron = {
      description = "nextcloud-cron.service";
      wantedBy = ["timers.target"];
      after = ["docker-nextcloud.service"];
      timerConfig.OnCalendar = "*:0/5"; # every 5 minutes
      timerConfig.Persistent = true;
    };
    systemd.services.nextcloud-cron = {
      description = "Create the nextcloud database and user";
      serviceConfig.Type = "oneshot";
      script = ''
        ${config.virtualisation.docker.package}/bin/docker exec -t --user www-data nextcloud php cron.php
      '';
    };

    services.nextcloud.trusted-domains = [
      "nextcloud.${config.networking.fqdn}"
      "cloud.${cfg.fqdn}"
      "nextcloud.${cfg.fqdn}"
    ];

    virtualisation.oci-containers.containers.nextcloud = {
      image = "nextcloud:24";
      dependsOn = ["postgres" "redis"];
      ports = ["${port}:80"];
      # user = "${uid}:${gid}";
      volumes = [
        "${config.mine.persistPath}/nextcloud:/var/www/html"
        "${config.age.secrets.redisPass.path}:${config.age.secrets.redisPass.path}"
        "${config.age.secrets.nextcloudPgPass.path}:${config.age.secrets.nextcloudPgPass.path}"
      ];
      environment = {
        NEXTCLOUD_TRUSTED_DOMAINS = toString cfg.trusted-domains;
        POSTGRES_HOST = "postgres:${toString config.services.postgresql.port}";
        POSTGRES_DB = config.services.nextcloud.config.dbname;
        POSTGRES_USER = config.services.nextcloud.config.dbuser;
        POSTGRES_PASSWORD_FILE = config.age.secrets.nextcloudPgPass.path;
        REDIS_HOST = "redis";
        REDIS_HOST_PORT = toString config.services.redis.servers.default.port;
        # REDIS_HOST_PASSWORD_FILE = config.age.secrets.redisPass.path;
      };
      extraOptions = ["--network=postgres"];
    };

    services.nginx.virtualHosts = let
      base-config = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          add_header Referrer-Policy                      "no-referrer"   always;
          add_header X-Content-Type-Options               "nosniff"       always;
          add_header X-Download-Options                   "noopen"        always;
          add_header X-Frame-Options                      "SAMEORIGIN"    always;
          add_header X-Permitted-Cross-Domain-Policies    "none"          always;
          add_header X-Robots-Tag                         "none"          always;
          add_header X-XSS-Protection                     "1; mode=block" always;
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";

          client_max_body_size 512M;
          client_body_timeout 300s;

          access_log /var/log/nginx/nextcloud.access.log;
          error_log /var/log/nginx/nextcloud.error.log;

          server_tokens off;
        '';
        locations."/" = {
          priority = 1;
          proxyPass = "http://127.0.0.1:${port}";
          extraConfig = ''
            if ( $http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/$is_args$args;
            }
          '';
        };
        locations."/robots.txt" = {
          extraConfig = ''
            allow all;
            log_not_found off;
            access_log off;
          '';
        };
        locations."^~ /.well-known" = {
          extraConfig = ''
            location = /.well-known/carddav { return 301 /remote.php/dav/; }
            location = /.well-known/caldav  { return 301 /remote.php/dav/; }

            location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

            # Let Nextcloud's API for `/.well-known` URIs handle all other
            # requests by passing them to the front-end controller.
            return 301 /index.php$request_uri;
          '';
        };
        locations."~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)".return = "404";
        locations."~ ^/(?:\\.|autotest|occ|issue|indie|db_|console)".return = "404";
      };
    in
      lib.pipe cfg.trusted-domains [
        (builtins.map (s: {
          name = s;
          value = base-config;
        }))
        builtins.listToAttrs
      ]
      // {
        # home page
        "${cfg.fqdn}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            index = "index.html";
            root = pkgs.writeTextDir "index.html" ''
                <!DOCTYPE html>
                <html lang="en-US">
                  <head>
                    <meta charset="utf-8">
                    <title>${cfg.fqdn}</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                    html { font-size: 16px; }
                    body {
                      font-size: 2rem;
                      font-family: sans-serif;
                      text-align: center;
                      background: pink;
                    }
                    :root {
                      --color: cornflowerblue;
                    }
                    a, a:visited {
                      display: inline-block;
                      text-decoration: none;
                      color: var(--color);
                      border-bottom: 2px dotted var(--color);
                      margin: 0.2em;
                      padding: 0.2em;
                    }
                    a:hover {
                      --color: blue;
                    }
                    .dev {
                      font-size: 1rem;
                      margin-top: 100vh;
                    }
                    .dev {
                      --color: #ccc;
                      color: var(--color);
                    }
                    </style>
                  </head>
                  <body>
                    <section>
                      <h1>🤗 ${cfg.fqdn} 🦄</h1>
                      <p>Huddle Cloud Puddle</p>
                      <div>
                        <a href="https://cloud.${cfg.fqdn}/" > ☁️  Cloud </a>
                </div>
                </section>
              <section class=dev>
              <h2>⚙ dev</h1>
              </section>
              </body>
              </html>
            '';
          };
        };
      };
  };
}
