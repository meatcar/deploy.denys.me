{ config, lib, pkgs, ... }:

{
  options =
    let
      inherit (lib) mkOption types;
    in
    {
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
      passwordFile = config.sops.secrets."cloudflare-key".path;
      domains = [ config.fqdn ];
      zone = config.domain;
    };

    services.cfdyndns = {
      enable = true;
      email = config.cloudflare.email;
      apikeyFile = config.sops.secrets."cloudflare-key".path;
      records = [ config.fqdn ];
    };
  };
}
