# fix for https://github.com/NixOS/nixpkgs/issues/104750
{
  config,
  lib,
  ...
}: {
  systemd.services =
    lib.attrsets.mapAttrs'
    (name: _: {
      name = "docker-${name}";
      value = {
        serviceConfig = {
          StandardOutput = lib.mkForce "journal";
          StandardError = lib.mkForce "journal";
        };
      };
    })
    config.virtualisation.oci-containers.containers;
}
