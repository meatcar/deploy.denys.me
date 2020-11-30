{ config, pkgs, ... }:
{
  services.jellyfin = {
    enable = true;
  };
  services.nginx.virtualHosts."jellyfin.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    # Hack for chromecast, pending fix. source:
    # https://github.com/jellyfin/jellyfin/issues/3852#issuecomment-675027272
    locations."=/System/Info/Public".extraConfig =
      let
        hack = pkgs.writeText "hack.json" ''
          {"LocalAddress": "https://jellyfin.cube.denys.me","ServerName": "cube","Version": "10.5.5","ProductName": "Jellyfin Server","OperatingSystem": "Linux","Id": "f493033cefec41388dd38783a66f50cc"}
        '';
      in
      ''
        default_type "application/json; charset=utf-8";
        alias ${hack};
      '';
    locations."/".proxyPass = "http://127.0.0.1:8096";
  };
  networking.firewall.allowedUDPPorts = [ 1900 7359 ];
}
