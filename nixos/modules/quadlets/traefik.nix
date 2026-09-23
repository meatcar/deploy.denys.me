# Rootless Traefik reverse proxy via Podman Quadlet.
# Listens on high ports (8080/8443); DNAT in default.nix redirects public
# 80/443 to these.
#
# Routing comes from a static file provider generated below, NOT from the
# podman/docker API. Traefik is the only internet-facing process on this host,
# and a container-runtime socket in its filesystem meant an RCE could create a
# privileged container, read every agenix secret and exfiltrate the databases.
# Traefik now has no access to the podman API at all; the trade-off is that new
# routes are a config change here rather than a label on the container.
#
# Both public sites are proxied by Cloudflare so the host firewall can reject
# every direct-origin request. Certificates therefore use Cloudflare DNS-01;
# inbound ACME challenges cannot reach this origin.
{
  config,
  pkgs,
  ...
}:
let
  persistDir = "${config.mine.persistPath}/traefik";
  podCfg = config.home-manager.users.pod.virtualisation.quadlet;
  publicRoutes = import ./public-routes.nix;
  traefikConfig = pkgs.writeText "traefik.yml" ''
    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
      websecure:
        address: ":443"
        http:
          # Match the same path that nginx/Laravel will interpret. In particular,
          # reject double-encoding before either backend can decode it again.
          sanitizePath: true
          encodedCharacters:
            allowEncodedSlash: false
            allowEncodedBackSlash: false
            allowEncodedNullCharacter: false
            allowEncodedSemicolon: false
            allowEncodedPercent: false
            allowEncodedQuestionMark: false
            allowEncodedHash: false
        forwardedHeaders:
          # Rootlessport is Traefik's immediate peer and therefore hides
          # Cloudflare's network address. The host firewall authenticates the
          # network path before Traefik consumes forwarded headers.
          trustedIPs:
            - 10.89.1.0/24
      netbird:
        address: ":9443"
    providers:
      file:
        directory: /etc/traefik/dynamic
    certificatesResolvers:
      le-dns:
        acme:
          email: ${config.mine.notificationEmail}
          storage: /acme.json
          dnsChallenge:
            provider: cloudflare
  '';

  # Service URLs resolve over the shared `proxy` network via podman's DNS;
  # each name is the container name declared in the owning module.
  traefikDynamicConfig = pkgs.writeText "traefik-dynamic.yml" ''
    http:
      routers:
        larapaper:
          rule: "Host(`trmnl.denys.me`) && (${publicRoutes.larapaper})"
          entryPoints:
            - websecure
          service: larapaper
          tls:
            certResolver: le-dns

        larapaper-admin:
          rule: "Host(`trmnl.vpn.denys.me`)"
          entryPoints:
            - netbird
          service: larapaper
          tls:
            certResolver: le-dns

        invoiceninja:
          # Keep the SNS controller off the public browser hostname. Its only
          # route is the source-restricted billing-sns router below.
          rule: "Host(`billing.denys.me`) && (${publicRoutes.invoiceninja})"
          entryPoints:
            - websecure
          service: invoiceninja
          middlewares:
            - invoiceninja-headers
            - invoiceninja-ratelimit
          tls:
            certResolver: le-dns

        invoiceninja-admin:
          rule: "Host(`billing.vpn.denys.me`) && !PathPrefix(`/api/v1/sns_webhook`)"
          entryPoints:
            - netbird
          service: invoiceninja
          middlewares:
            - invoiceninja-headers
          tls:
            certResolver: le-dns

        invoiceninja-mailer-oauth:
          # v5.13.29 starts Socialite state on the current host but always uses
          # APP_URL for the callback. Move to that host before creating state.
          # routes/web.php requires no private session here; OAuth::handleAuth
          # resolves the existing account by the verified provider identity.
          rule: "Host(`billing.vpn.denys.me`) && (Method(`GET`) || Method(`HEAD`)) && (Path(`/auth/google`) || Path(`/auth/microsoft`))"
          priority: 100
          entryPoints:
            - netbird
          service: noop@internal
          middlewares:
            - invoiceninja-headers
            - invoiceninja-mailer-origin
          tls:
            certResolver: le-dns

        invoiceninja-sns:
          rule: "Host(`billing-sns.denys.me`) && Path(`/api/v1/sns_webhook`) && Method(`POST`)"
          priority: 100
          entryPoints:
            - websecure
          service: invoiceninja
          tls:
            certResolver: le-dns

      services:
        larapaper:
          loadBalancer:
            servers:
              - url: "http://larapaper:8080"

        invoiceninja:
          loadBalancer:
            servers:
              - url: "http://invoiceninja-nginx:80"

      middlewares:
        invoiceninja-mailer-origin:
          redirectRegex:
            # The router restricts methods and paths; preserve the raw query,
            # including react=true, without accepting a caller-supplied host.
            regex: '^https://[^/]+(/.*)$'
            replacement: 'https://billing.denys.me''${1}'
            permanent: false

        invoiceninja-headers:
          headers:
            # Invoice Ninja terminates nothing itself; these are the only
            # security headers on the billing origin.
            stsSeconds: 31536000
            # Scoped to this host on purpose: trmnl and the apex are served by
            # other origins that are not all HTTPS-only yet.
            stsIncludeSubdomains: false
            contentTypeNosniff: true
            referrerPolicy: "strict-origin-when-cross-origin"
            # SAMEORIGIN rather than DENY: the client portal renders invoice
            # PDF previews in same-origin iframes.
            customResponseHeaders:
              X-Frame-Options: "SAMEORIGIN"

        invoiceninja-ratelimit:
          rateLimit:
            # billing is behind Cloudflare's proxy, so every request arrives
            # from a Cloudflare edge IP. Keying on the default client IP would
            # pool all users into a handful of buckets and throttle everyone at
            # once, so key on the real client address instead.
            sourceCriterion:
              requestHeaderName: "Cf-Connecting-Ip"
            # Generous enough for payment-gateway webhook bursts and a browser
            # loading a page's worth of assets, while still capping brute force
            # against the login form.
            average: 100
            period: 1s
            burst: 200
  '';
in
{
  # Persist dir and acme.json owned by pod so rootless traefik can write them.
  systemd.tmpfiles.rules = [
    "d ${persistDir} 0750 pod pod - -"
    "f ${persistDir}/acme.json 0600 pod pod - -"
  ];

  home-manager.users.pod.virtualisation.quadlet.containers.traefik = {
    autoStart = true;
    containerConfig = {
      image = "traefik:v3.7.5";
      publishPorts = [
        "8080:80"
        "8443:443"
        "9443:9443"
      ];
      volumes = [
        "${traefikConfig}:/etc/traefik/traefik.yml:ro"
        "${traefikDynamicConfig}:/etc/traefik/dynamic/main.yml:ro"
        "${persistDir}/acme.json:/acme.json"
        # DNS-01 credential. Mounted as a file and referenced by *_FILE so the
        # token never lands in the container's environment or in the nix store.
        "${config.age.secrets.cloudflareToken.path}:/run/secrets/cloudflareToken:ro"
      ];
      environments = {
        # lego reads <VAR>_FILE and strips the trailing newline.
        CF_DNS_API_TOKEN_FILE = "/run/secrets/cloudflareToken";
      };
      networks = [ podCfg.networks.proxy.ref ];
    };
    serviceConfig = {
      Restart = "on-failure";
      MemoryHigh = "192M";
      MemoryMax = "256M";
    };
  };
}
