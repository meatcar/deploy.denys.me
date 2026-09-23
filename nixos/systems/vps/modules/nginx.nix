{
  config,
  lib,
  specialArgs,
  ...
}:
let
  inherit (config.networking) domain;
in
{
  imports = [
    ../../../modules/nginx.nix
    ../../../modules/nginx-sni-proxy.nix
    ../../../modules/private-access
  ];

  mine.privateAccess.httpHosts = [ "znc.${domain}" ];
  mine.nginx-sni-proxy = {
    enable = true;
    proxies = {
      "plex.cube.${domain}" = {
        host = "100.72.190.168";
      };
      "ombi.cube.${domain}" = {
        host = "100.72.190.168";
      };
    };
  };

  services.nginx = {
    virtualHosts =
      lib.genAttrs (import ../../cube/private-http-hosts.nix "cube.${domain}") (_: {
        locations."^~ /.well-known/acme-challenge/".proxyPass = "http://100.72.190.168";
        locations."/".return = "404";
      })
      // {
        ${domain} = {
          enableACME = true;
          forceSSL = true;
          serverAliases = [
            "www.${domain}"
          ];
          root = specialArgs.inputs.website;
          extraConfig = ''
            index index.html;
            if ($ssl_server_name != $host) { return 421; }
          '';
        };
      };
  };
}
