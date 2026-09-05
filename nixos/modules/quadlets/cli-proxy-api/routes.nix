{ publicHost, managementHost }:
{
  http = {
    routers = {
      cli-proxy-api = {
        rule = "Host(`${publicHost}`) && (PathPrefix(`/v1/`) || PathPrefix(`/v1beta/`) || PathPrefix(`/openai/v1/videos`) || Path(`/backend-api/codex/responses`) || Path(`/backend-api/codex/responses/compact`) || Path(`/backend-api/codex/alpha/search`))";
        entryPoints = [ "websecure" ];
        service = "cli-proxy-api";
        tls.certResolver = "le-dns";
      };
      cli-proxy-management = {
        rule = "Host(`${managementHost}`)";
        entryPoints = [ "netbird" ];
        service = "cpa-manager-plus";
        tls.certResolver = "le-dns";
      };
      pi-bridge = {
        rule = "Host(`${publicHost}`) && Method(`GET`) && (Path(`/v0/resource/plugins/pi-bridge/capabilities`) || Path(`/v0/resource/plugins/pi-bridge/usage`) || Path(`/v0/resource/plugins/pi-bridge/well-known`))";
        entryPoints = [ "websecure" ];
        service = "cli-proxy-api";
        tls.certResolver = "le-dns";
      };
    };
    services.cli-proxy-api.loadBalancer.servers = [
      { url = "http://cli-proxy-api:8317"; }
    ];
    services.cpa-manager-plus.loadBalancer.servers = [
      { url = "http://cpa-manager-plus:18317"; }
    ];
  };
}
