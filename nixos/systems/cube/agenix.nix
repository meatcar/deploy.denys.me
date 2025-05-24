{
  config,
  lib,
  ...
}:
let
  cfg = config.age;
in
{
  options.age.secrets = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          { config, ... }:
          {
            options = {
              action = lib.mkOption {
                type = nullOr str;
                default = null;
                description = "Action to run when secret is updated.";
                example = "systemctl restart wireguard-wg0.service";
              };
              service = lib.mkOption {
                type = nullOr str;
                default = null;
                description = "The systemd service that uses this secret.";
                example = "wireguard-wg0";
              };
            };

            config = {
              action = lib.mkIf (config.service != null) (
                lib.mkOverride 980 "systemctl restart ${config.service}.service"
              );
            };
          }
        )
      );
  };

  config = {
    systemd = lib.mkMerge (
      lib.mapAttrsToList (
        name:
        {
          action,
          path,
          ...
        }:
        {
          paths."${name}-watcher" = {
            wantedBy = [ "multi-user.target" ];
            pathConfig = {
              PathModified = path;
            };
          };

          services."${name}-watcher" = {
            serviceConfig = {
              Type = "oneshot";
              ExecStart = action;
            };
          };
        }
      ) cfg.secrets
    );
    age.secrets = {
      ssmtpPass = {
        file = ../../../secrets/ssmtp-pass.age;
        mode = "0444";
      };
      transmissionUser.file = ../../../secrets/transmission-user.age;
      transmissionPass.file = ../../../secrets/transmission-pass.age;
      hashedPassword.file = ../../../secrets/hashed-password.age;
      cloudflareKey.file = ../../../secrets/cloudflare-key.age;
      wgPrivateKey.file = ../../../secrets/wg-cube-private-key.age;
      redisConf.file = ../../../secrets/redis-conf.age;
      redisPass = {
        file = ../../../secrets/redis-pass.age;
        owner = config.mine.storageUser;
        group = config.mine.storageGroup;
      };
      postgresPass.file = ../../../secrets/postgres-pass.age;
      nextcloudPgPass.file = ../../../secrets/nextcloudPgPass.age;
      freshrssPgPass.file = ../../../secrets/freshrssPgPass.age;
    };
  };
}
