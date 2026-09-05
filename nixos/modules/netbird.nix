_: {
  services.netbird = {
    ui.enable = false;
    clients.default = {
      name = "default";
      interface = "wt0";
      # NOTE: Cube uses UDP/51820; the VPS uses UDP/51821 for WireGuard.
      port = 51822;
      openInternalFirewall = false;
      config = {
        ManagementURL = {
          Scheme = "https";
          Host = "api.netbird.io:443";
        };
        ServerSSHAllowed = false;
        DisableDNS = true;
        DisableServerRoutes = true;
        DisableClientRoutes = true;
      };
    };
  };
}
