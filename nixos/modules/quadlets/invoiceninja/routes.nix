let
  publicRoutes = import ./public-routes.nix;
  tls.certResolver = "le-dns";
in
{
  http = {
    routers = {
      invoiceninja = {
        # NOTE: SNS stays off the browser host. Only invoiceninja-sns serves it.
        rule = "Host(`billing.denys.me`) && (${publicRoutes.rule})";
        entryPoints = [ "websecure" ];
        service = "invoiceninja";
        middlewares = [
          "invoiceninja-headers"
          "invoiceninja-ratelimit"
        ];
        inherit tls;
      };
      invoiceninja-admin = {
        rule = "Host(`billing.vpn.denys.me`) && !PathPrefix(`/api/v1/sns_webhook`)";
        entryPoints = [ "netbird" ];
        service = "invoiceninja";
        middlewares = [ "invoiceninja-headers" ];
        inherit tls;
      };
      invoiceninja-mailer-oauth = {
        # NOTE: v5.13.29 sends the OAuth callback to APP_URL. Start there so state and callback share a session.
        rule = "Host(`billing.vpn.denys.me`) && (Method(`GET`) || Method(`HEAD`)) && (Path(`/auth/google`) || Path(`/auth/microsoft`))";
        priority = 100;
        entryPoints = [ "netbird" ];
        service = "noop@internal";
        middlewares = [
          "invoiceninja-headers"
          "invoiceninja-mailer-origin"
        ];
        inherit tls;
      };
      invoiceninja-sns = {
        rule = "Host(`billing-sns.denys.me`) && Path(`/api/v1/sns_webhook`) && Method(`POST`)";
        priority = 100;
        entryPoints = [ "websecure" ];
        service = "invoiceninja";
        inherit tls;
      };
    };

    services.invoiceninja.loadBalancer.servers = [ { url = "http://invoiceninja-nginx:80"; } ];

    middlewares = {
      # NOTE: The router fixes method and path. Keep the raw query, never the caller's host.
      invoiceninja-mailer-origin.redirectRegex = {
        regex = "^https://[^/]+(/.*)$";
        replacement = "https://billing.denys.me\${1}";
        permanent = false;
      };
      invoiceninja-headers.headers = {
        stsSeconds = 31536000;
        # NOTE: Other denys.me origins are not all HTTPS-only.
        stsIncludeSubdomains = false;
        contentTypeNosniff = true;
        referrerPolicy = "strict-origin-when-cross-origin";
        # NOTE: The client portal previews invoice PDFs in same-origin iframes.
        customResponseHeaders.X-Frame-Options = "SAMEORIGIN";
      };
      invoiceninja-ratelimit.rateLimit = {
        # NOTE: Cloudflare proxies every request. Key on the client, not the edge.
        sourceCriterion.requestHeaderName = "Cf-Connecting-Ip";
        average = 100;
        period = "1s";
        burst = 200;
      };
    };
  };
}
