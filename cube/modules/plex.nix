{ config, pkgs, inputs, ... }:
let
  # copy a store path to a have a new name.
  # Used to rename flake input paths from `<hash>-source`, since
  # services.plex.managePlugins calls `basename` on the path, and plex expects
  # the  directory name to be formated like `<name>.bundle`
  renamePath = path: name: pkgs.runCommand name { inherit path name; } ''
    mkdir -p $out
    cp -r $path/* $out
  '';
in
{
  config = {
    systemd.tmpfiles.rules = [
      "L /var/lib/plex - - - - ${config.persistPath}/var/lib/plex"
    ];

    nixpkgs.config.allowUnfree = true;

    services.plex = {
      enable = true;
      openFirewall = true;
      extraPlugins = [ (renamePath inputs.plex-subzero "Sub-Zero.bundle") ];
    };

    services.nginx = {
      clientMaxBodySize = "100M";
      virtualHosts."plex.${config.fqdn}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:32400";
          proxyWebsockets = true;
        };
        extraConfig = ''
          proxy_buffering off;
          send_timeout 100m;
        '';
      };
    };
  };
}
