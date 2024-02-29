{
  config,
  lib,
  ...
}: {
  options = {
    me.tailscale.tailnet = lib.mkOption {
      type = lib.types.str;
      description = "The main tailscale tailnet all hosts belong to.";
    };
  };

  config = {
    services.tailscale.enable = true;
    # services.nginx.tailscaleAuth = {
    #   enable = true;
    #   expectedTailnet = config.me.tailscale.tailnet;
    # };
  };
}
