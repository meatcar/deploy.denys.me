{
  config,
  pkgs,
  specialArgs,
  ...
}: let
  app = specialArgs.inputs.transit-dashboard;
  volumes = "${config.mine.persistPath}/transit-dashboard";
in {
  config = {
    systemd.tmpfiles.rules = [
      "d ${volumes} 0755 - - - -"
    ];
    virtualisation.oci-containers.containers.transit-dashboard = {
      image = "meatcar/transit-dashboard:latest";
      imageFile = app.packages.${pkgs.hostPlatform.system}.dockerImage;
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
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
      ];
    };
  };
}
