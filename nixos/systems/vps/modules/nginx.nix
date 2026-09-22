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
    ../../../modules/nginx-sni-proxy.nix
  ];

  mine.nginx-sni-proxy = {
    enable = true;
    proxies = {
      "cube.${domain}" = {
        host = "100.72.190.168";
      };
      "huddle.win" = {
        host = "100.72.190.168";
      };
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
