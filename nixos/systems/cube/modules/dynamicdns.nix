{
  config,
  lib,
  pkgs,
  ...
}: {
  options = let
    inherit (lib) mkOption types;
  in {
    cloudflare = {
      email = mkOption {
        type = types.str;
        description = "Cloudflare email";
      };
      key = mkOption {
        type = types.str;
        description = "Cloudflare API Key";
      };
    };
  };
  config = {
    services.ddclient = {
      enable = false;
      protocol = "cloudflare";
      username = config.cloudflare.email;
      passwordFile = config.age.secrets.cloudflareKey.path;
      domains = [config.networking.fqdn];
      zone = config.networking.domain;
    };

    services.cfdyndns = {
      enable = true;
      email = config.cloudflare.email;
      apikeyFile = config.age.secrets.cloudflareKey.path;
      records = [config.networking.fqdn];
    };
  };
}
