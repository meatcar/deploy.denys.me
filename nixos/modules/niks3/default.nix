{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.niks3;
  deployment = lib.importJSON config.mine.niks3.deploymentFile;
  url = "https://${deployment.host}";
  secret = name: {
    file = ../../../secrets/${name}.age;
    owner = cfg.user;
  };
  routes = pkgs.writeText "niks3-routes.yml" (
    builtins.toJSON (
      import ./routes.nix {
        inherit (deployment) host;
        port = lib.last (lib.splitString ":" deployment.listen);
      }
    )
  );
in
{
  imports = [
    inputs.niks3.nixosModules.niks3
    ./policy.nix
  ];

  options.mine.niks3.deploymentFile = lib.mkOption {
    type = lib.types.path;
    description = "Non-secret niks3 deployment profile.";
  };

  config = {
    age.secrets = {
      niks3-api-token = secret "niks3-api-token";
      niks3-sign-key = secret "niks3-sign-key";
      niks3-r2-access-key = secret "niks3-r2-access-key";
      niks3-r2-secret-key = secret "niks3-r2-secret-key";
    };

    services.niks3 = {
      # NOTE: Rootless Traefik reaches the host on its private IP, not on loopback.
      httpAddr = deployment.listen;
      s3 = {
        endpoint = deployment.s3_endpoint;
        inherit (deployment) bucket;
        region = "auto";
        accessKeyFile = config.age.secrets.niks3-r2-access-key.path;
        secretKeyFile = config.age.secrets.niks3-r2-secret-key.path;
      };
      apiTokenFile = config.age.secrets.niks3-api-token.path;
      signKeyFiles = [ config.age.secrets.niks3-sign-key.path ];
      cacheUrl = url;
      serverUrl = url;
    };

    systemd.sockets.niks3.socketConfig.FreeBind = true;
    systemd.services.niks3 = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    home-manager.users.pod.virtualisation.quadlet.containers.traefik.containerConfig.volumes = [
      "${routes}:/etc/traefik/dynamic/niks3.yml:ro"
    ];
  };
}
