# Public rule reviewed against usetrmnl/larapaper 0.37.1 routes/api.php. Re-review on upgrades.
let
  read = "(Method(`GET`) || Method(`HEAD`))";
  uuid = "[0-9a-fA-F-]{36}";
  publicRule = builtins.concatStringsSep " || " [
    "(${read} && (Path(`/api/setup`) || Path(`/api/display`) || Path(`/api/current_screen`)))"
    "(Method(`POST`) && (Path(`/api/log`) || Path(`/api/screens`)))"
    "(${read} && PathRegexp(`^/storage/(images|firmwares)/.+$`))"
    # Existing public integrations use UUIDs, not the Sanctum admin routes.
    "((${read} || Method(`POST`)) && PathRegexp(`^/api/custom_plugins/${uuid}$`))"
    "(Method(`POST`) && PathRegexp(`^/api/(plugins/${uuid}/webhook|plugin_settings/${uuid}/image)$`))"
    "(${read} && PathRegexp(`^/api/display/${uuid}/alias$`))"
  ];
in
{
  http = {
    routers = {
      larapaper = {
        rule = "Host(`trmnl.denys.me`) && (${publicRule})";
        entryPoints = [ "websecure" ];
        service = "larapaper";
        tls.certResolver = "le-dns";
      };
      larapaper-admin = {
        rule = "Host(`trmnl.vpn.denys.me`)";
        entryPoints = [ "netbird" ];
        service = "larapaper";
        tls.certResolver = "le-dns";
      };
    };
    services.larapaper.loadBalancer.servers = [ { url = "http://larapaper:8080"; } ];
  };
}
