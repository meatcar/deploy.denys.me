{ config, pkgs, lib, ... }:
{
  systemd.tmpfiles.rules = [
    "L /var/lib/docker - - - - /persist/var/lib/docker"
  ];
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  systemd.services =
    lib.pipe
      config.virtualisation.oci-containers.containers
      [
        builtins.attrNames
        (map
          (name: {
            name = "docker-${name}";
            value = {
              serviceConfig = {
                StandardOutput = lib.mkForce "journal";
                StandardError = lib.mkForce "journal";
              };
            };
          }))
        builtins.listToAttrs
      ];
}
