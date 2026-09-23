{ config, lib, ... }:
let
  containers = [
    "gluetun"
    "organizr"
    "plex"
    "ombi"
    "sonarr"
    "radarr"
    "bazarr"
    "tautulli"
    "scrutiny"
    "calibre-web"
  ];
  units = map (name: "docker-${name}") containers;
in
{
  virtualisation.oci-containers.containers = lib.genAttrs containers (_: {
    networks = [ "media" ];
  });
  systemd.services = {
    docker-media-network = {
      requires = [ "docker.service" ];
      after = [ "docker.service" ];
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = builtins.readFile ./create-network.sh;
    };
  }
  // lib.genAttrs units (_: {
    requires = [ "docker-media-network.service" ];
    after = [ "docker-media-network.service" ];
  });
}
