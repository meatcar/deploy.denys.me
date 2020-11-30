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
      username = builtins.readFile "";
      password = builtins.readFile "";
      domains = [ config.fqdn ];
      zone = config.domain;
    };

    services.cfdyndns = {
      enable = true;
      apikey = config.cloudflare.key;
      email = config.cloudflare.email;
      records = [ config.fqdn ];
    };
  };
}
