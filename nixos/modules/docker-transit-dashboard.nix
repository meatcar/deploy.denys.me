{
  config,
  ...
}:
let
  volumes = "${config.mine.persistPath}/transit-dashboard";
in
{
  config = {
    # The container runs tailscale, which needs a tun device. Loading it on the
    # host means the container does not need CAP_SYS_MODULE to modprobe it
    # itself. (TUN is currently built into this kernel, so this is a no-op
    # today; it is declared so the capability stays droppable if that changes.)
    boot.kernelModules = [ "tun" ];

    systemd.tmpfiles.rules = [
      "d ${volumes} 0755 - - - -"
    ];
    virtualisation.oci-containers.containers.transit-dashboard = {
      image = "meatcar/transit-dashboard:latest";
      hostname = "transit-dashboard"; # for tailscale
      volumes = [
        "/dev/net/tun:/dev/net/tun"
        "${volumes}/tailscale:/var/lib/tailscale"
        "${volumes}/cache:/app/cache"
      ];
      environment = {
        PUID = toString config.ids.uids.${config.mine.storageUser};
        PGID = toString config.ids.gids.${config.mine.storageGroup};
      };
      environmentFiles = [
        config.age.secrets.transitDashboardEnv.path
      ];
      extraOptions = [
        # NET_ADMIN is required: tailscaled configures its own tun interface.
        "--cap-add=NET_ADMIN"
        # SYS_MODULE deliberately NOT granted. It lets a container load kernel
        # modules, which is equivalent to host root, and this container tracks a
        # mutable :latest tag. The host loads tun instead (see kernelModules).
      ];
    };
  };
}
