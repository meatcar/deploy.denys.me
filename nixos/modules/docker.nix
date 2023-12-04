{ config, ... }:
{
  systemd.tmpfiles.rules = [
    "L /var/lib/docker - - - - ${config.mine.persistPath}/docker"
  ];
  virtualisation.oci-containers.backend = "docker";
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
}
