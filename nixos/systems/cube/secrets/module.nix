{
  config,
  lib,
  ...
}: let
  cfg = config.age;
in {
  options.age.secrets = lib.mkOption {
    type = with lib.types;
      attrsOf (submodule ({config, ...}: {
        options = {
          action = lib.mkOption {
            type = nullOr string;
            default = null;
            description = "Action to run when secret is updated.";
            example = "systemctl restart wireguard-wg0.service";
          };
          service = lib.mkOption {
            type = nullOr string;
            default = null;
            description = "The systemd service that uses this secret.";
            example = "wireguard-wg0";
          };
        };

        config = {
          action =
            lib.mkIf (config.service != null)
            (lib.mkOverride 980 "systemctl restart ${config.service}.service");
        };
      }));
  };

  config = {
    systemd =
      lib.mkMerge
      (lib.mapAttrsToList
        (name: {
          action,
          path,
          ...
        }: {
          paths."${name}-watcher" = {
            wantedBy = ["multi-user.target"];
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
        })
        cfg.secrets);
    age.secrets = {
      ssmtpPass = {
        file = ./ssmtp-pass.age;
        mode = "0444";
      };
      transmissionUser.file = ./transmission-user.age;
      transmissionPass.file = ./transmission-pass.age;
      hashedPassword.file = ./hashed-password.age;
      cloudflareKey.file = ./cloudflare-key.age;
      wgPrivateKey.file = ./wg-private-key.age;
      redisConf.file = ./redis-conf.age;
      redisPass = {
        file = ./redis-pass.age;
        owner = config.mine.storageUser;
        group = config.mine.storageGroup;
      };
      postgresPass.file = ./postgres-pass.age;
      nextcloudPgPass.file = ./nextcloudPgPass.age;
      freshrssPgPass.file = ./freshrssPgPass.age;
      transitDashboardEnv.file = ./transitDashboardEnv.age;
    };
  };
}
