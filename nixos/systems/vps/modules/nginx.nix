{
  config,
  specialArgs,
  ...
}:
let
  inherit (config.networking) domain;
in
{
  imports = [
    ../../../modules/nginx.nix
    ../../../modules/private-access
  ];

  mine.privateAccess.httpHosts = [ "znc.${domain}" ];

  services.nginx = {
    virtualHosts = {
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
