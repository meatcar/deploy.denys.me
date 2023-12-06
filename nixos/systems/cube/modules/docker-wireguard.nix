{ config, pkgs, lib, ... }:
{
  boot.kernelModules = [ "wireguard" ];
  systemd.tmpfiles.rules = [
    "d ${config.mine.persistPath}/wireguard 0755 - - - -"
  ];

  virtualisation.oci-containers.containers.wireguard = {
    image = "ghcr.io/linuxserver/wireguard";
    ports = [ "51820:51820/udp" ];
    volumes = [
      "/sys:/sys:rw"
      "/run/booted-system/kernel-modules/lib/modules:/lib/modules"
      "${config.mine.persistPath}/wireguard:/config"
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
      "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
    ];
  };
}
