{ config, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "L /var/lib/docker - - - - /persist/var/lib/docker"
  ];
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
}
