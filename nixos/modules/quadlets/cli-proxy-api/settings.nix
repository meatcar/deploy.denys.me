{ publicHost, bridgeVersion }:
{
  host = "0.0.0.0";
  port = 8317;
  auth-dir = "/CLIProxyAPI/state/auth";
  remote-management = {
    allow-remote = true;
    disable-control-panel = true;
  };
  ws-auth = true;
  usage-statistics-enabled = true;
  quota-exceeded = {
    switch-project = true;
    switch-preview-model = false;
  };
  plugins = {
    enabled = true;
    dir = "/plugins";
    configs.pi-bridge = {
      enabled = true;
      priority = 3;
      allow_all_api_keys = true;
      show_extra_analytics = true;
      store.version = bridgeVersion;
      advanced = builtins.toJSON {
        management_key_file = "/CLIProxyAPI/state/management-key";
        cpam_admin_key_file = "/CLIProxyAPI/state/manager/admin-key";
        cpam_url = "http://cpa-manager-plus:18317";
        public_base_url = "https://${publicHost}/v1";
      };
    };
  };
}
