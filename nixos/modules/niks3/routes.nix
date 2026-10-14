{ host, port }:
{
  http = {
    routers.niks3 = {
      rule = "Host(`${host}`) && !PathPrefix(`/metrics`)";
      entryPoints = [ "websecure" ];
      service = "niks3";
      middlewares = [ "niks3-no-store" ];
      tls.certResolver = "le-dns";
    };
    services.niks3.loadBalancer.servers = [ { url = "http://host.containers.internal:${port}"; } ];
    # NOTE: Reads are gated. A shared edge cache must not replay them.
    middlewares.niks3-no-store.headers.customResponseHeaders.Cache-Control = "no-store";
  };
}
