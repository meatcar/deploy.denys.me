{ config, lib, pkgs, specialArgs, ... }:
let
  domain = config.networking.domain;
in
{
  imports = [
    ../../../modules/nginx.nix
    ../../../modules/nginx-sni-proxy.nix
  ];

  mine.nginx-sni-proxy = {
    enable = true;
    proxies = {
      "cube.${domain}" = { host = "10.100.0.4"; };
      "huddle.win" = { host = "10.100.0.4"; };
    };
  };

  services.nginx = {
    virtualHosts = {
      ${domain} = {
        enableACME = true;
        forceSSL = true;
        serverAliases = [
          "www.${domain}"
        ];
        root = specialArgs.inputs.website;
        extraConfig = "index index.html;";
      };
    };
  };
}
