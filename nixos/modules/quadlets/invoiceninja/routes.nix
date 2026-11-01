{
  http = {
    routers.invoiceninja = {
      rule = "Host(`billing.vpn.denys.me`)";
      entryPoints = [ "netbird" ];
      service = "invoiceninja";
      middlewares = [ "invoiceninja-headers" ];
      tls.certResolver = "le-dns";
    };
    services.invoiceninja.loadBalancer.servers = [ { url = "http://invoiceninja-nginx:80"; } ];
    middlewares.invoiceninja-headers.headers = {
      stsSeconds = 31536000;
      stsIncludeSubdomains = false;
      contentTypeNosniff = true;
      referrerPolicy = "strict-origin-when-cross-origin";
      # NOTE: Invoice PDF previews use same-origin iframes.
      customResponseHeaders.X-Frame-Options = "SAMEORIGIN";
    };
  };
}
