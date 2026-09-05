_:
let
  state = "/var/lib/vpn";
  backend = "Host(`vpn.denys.me`)";
  router = service: rule: priority: {
    inherit service rule priority;
    entryPoints = [ "websecure" ];
    tls.certResolver = "letsencrypt";
  };
in
{
  imports = [
    ./common.nix
  ];
  networking.hostName = "vpn";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      80
      443
    ];
    allowedUDPPorts = [
      3478
      51820
    ];
  };
  systemd.tmpfiles.rules = [
    "d ${state}/server 0700 root root -"
    "d ${state}/proxy 0700 root root -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      netbird-server = {
        image = "docker.io/netbirdio/netbird-server:0.78.1@sha256:3086534361a18573b85897383a0753a97b8c75d68dee9926fbd7eccab1f2fe89";
        ports = [
          "127.0.0.1:8081:80"
          "3478:3478/udp"
        ];
        volumes = [
          "${state}/server:/var/lib/netbird"
          "${state}/config.json:/etc/netbird/config.yaml:ro"
        ];
        cmd = [
          "--config"
          "/etc/netbird/config.yaml"
        ];
        environment.NB_SETUP_PAT_ENABLED = "true";
      };
      netbird-dashboard = {
        image = "docker.io/netbirdio/dashboard:v2.92.0@sha256:fa2d8b02a81761e4d2a22df4041d13316b7635f1e93273eafeb53d4991e55b5a";
        ports = [ "127.0.0.1:8080:80" ];
        environment = {
          NETBIRD_MGMT_API_ENDPOINT = "https://vpn.denys.me";
          NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://vpn.denys.me";
          AUTH_AUDIENCE = "netbird-dashboard";
          AUTH_CLIENT_ID = "netbird-dashboard";
          AUTH_AUTHORITY = "https://vpn.denys.me/oauth2";
          AUTH_SUPPORTED_SCOPES = "openid profile email groups";
          AUTH_REDIRECT_URI = "/nb-auth";
          AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
          USE_AUTH0 = "false";
          LETSENCRYPT_DOMAIN = "none";
        };
      };
      netbird-proxy = {
        image = "docker.io/netbirdio/reverse-proxy:0.78.1@sha256:d79cf51926c9d4640370c17b13904441f23e2dbb22cd67ff5a453f1cf7bd28b9";
        ports = [
          "127.0.0.1:8443:8443"
          "51820:51820/udp"
        ];
        volumes = [ "${state}/proxy:/certs" ];
        environmentFiles = [ "/etc/vpn/proxy.env" ];
        environment = {
          NB_PROXY_MANAGEMENT_ADDRESS = "https://vpn.denys.me:443";
          NB_PROXY_DOMAIN = "x.denys.me";
          NB_PROXY_ADDRESS = ":8443";
          NB_PROXY_CERTIFICATE_DIRECTORY = "/certs";
          NB_PROXY_ACME_CERTIFICATES = "true";
          NB_PROXY_ACME_CHALLENGE_TYPE = "tls-alpn-01";
          NB_PROXY_FORWARDED_PROTO = "https";
        };
      };
    };
  };
  systemd.services.podman-netbird-server.unitConfig.ConditionPathExists = "${state}/config.json";
  systemd.services.podman-netbird-proxy.unitConfig.ConditionPathExists = "/etc/vpn/proxy.env";

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure = {
          address = ":443";
          allowACMEByPass = true;
          transport.respondingTimeouts = {
            readTimeout = "0s";
            writeTimeout = "0s";
            idleTimeout = "0s";
          };
        };
      };
      certificatesResolvers.letsencrypt.acme = {
        email = "acme@denys.me";
        storage = "/var/lib/traefik/acme.json";
        tlsChallenge = { };
      };
      serversTransport.forwardingTimeouts = {
        responseHeaderTimeout = "0s";
        idleConnTimeout = "0s";
      };
    };
    dynamicConfigOptions = {
      http = {
        routers = {
          dashboard = router "dashboard" backend 1;
          api =
            router "server"
              "${backend} && (PathPrefix(`/api`) || PathPrefix(`/oauth2`) || PathPrefix(`/relay`) || PathPrefix(`/ws-proxy/`))"
              100;
          grpc =
            router "grpc"
              "${backend} && (PathPrefix(`/signalexchange.SignalExchange/`) || PathPrefix(`/management.ManagementService/`) || PathPrefix(`/management.ProxyService/`))"
              100;
          setup = (router "server" "${backend} && PathPrefix(`/api/setup`)" 200) // {
            middlewares = [ "local-only" ];
          };
        };
        middlewares.local-only.ipAllowList.sourceRange = [
          "127.0.0.1/32"
          "::1/128"
        ];
        services = {
          dashboard.loadBalancer.servers = [ { url = "http://127.0.0.1:8080"; } ];
          server.loadBalancer.servers = [ { url = "http://127.0.0.1:8081"; } ];
          grpc.loadBalancer.servers = [ { url = "h2c://127.0.0.1:8081"; } ];
        };
      };
      tcp = {
        routers.exposed = {
          rule = "HostSNIRegexp(`^[a-zA-Z0-9-]+[.]x[.]denys[.]me$`)";
          entryPoints = [ "websecure" ];
          tls.passthrough = true;
          service = "exposed";
        };
        services.exposed.loadBalancer.servers = [ { address = "127.0.0.1:8443"; } ];
      };
    };
  };

  services.restic.backups.vpn.paths = [ "${state}/config.json" ];
}
