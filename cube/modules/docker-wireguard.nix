{ config, pkgs, lib, ... }:
{
  boot.extraModulePackages = [ config.boot.kernelPackages.wireguard ];
  boot.kernelModules = [ "wireguard" ];
  systemd.tmpfiles.rules = [
    "d ${config.persistPath}/wireguard 0755 - - - -"
  ];

  virtualisation.oci-containers.containers.wireguard = {
    image = "linuxserver/wireguard";
    ports = [ "51820:51820/udp" ];
    volumes = [
      "/sys:/sys:rw"
      "/run/booted-system/kernel-modules/lib/modules:/lib/modules"
      "${config.persistPath}/wireguard:/config"
    ];
    environment = {
      PUID = "0";
      PGID = "0";
    };
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--cap-add=SYS_MODULE"
      "--privileged" # nescessary for the following
      "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
    ];
  };
}
