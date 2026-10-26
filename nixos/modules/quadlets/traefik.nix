# Rootless Traefik reverse proxy via Podman Quadlet.
# DNAT in default.nix redirects public 80/443 to 8080/8443.
# Each app module mounts its own routes into /etc/traefik/dynamic.
# NOTE: No podman API access. An RCE in the only internet-facing process must not control containers.
# NOTE: Cloudflare proxies all public sites and the firewall rejects direct-origin traffic, so ACME uses DNS-01.
{
  config,
  pkgs,
  ...
}:
let
  persistDir = "${config.mine.persistPath}/traefik";
  podCfg = config.home-manager.users.pod.virtualisation.quadlet;
  traefikConfig = pkgs.writeText "traefik.yml" (
    builtins.toJSON {
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
          http = {
            # NOTE: Reject double encoding before nginx or Laravel decode the path again.
            sanitizePath = true;
            encodedCharacters = {
              allowEncodedSlash = false;
              allowEncodedBackSlash = false;
              allowEncodedNullCharacter = false;
              allowEncodedSemicolon = false;
              allowEncodedPercent = false;
              allowEncodedQuestionMark = false;
              allowEncodedHash = false;
            };
          };
          # NOTE: Rootlessport hides Cloudflare's address. The host firewall authenticates the path.
          forwardedHeaders.trustedIPs = [ "10.89.1.0/24" ];
        };
        netbird.address = ":9443";
      };
      providers.file.directory = "/etc/traefik/dynamic";
      certificatesResolvers.le-dns.acme = {
        email = config.mine.notificationEmail;
        storage = "/acme.json";
        dnsChallenge.provider = "cloudflare";
      };
    }
  );
in
{
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
        "${persistDir}/acme.json:/acme.json"
        "${config.age.secrets.cloudflareToken.path}:/run/secrets/cloudflareToken:ro"
      ];
      # NOTE: lego reads <VAR>_FILE, which keeps the token out of the environment.
      environments.CF_DNS_API_TOKEN_FILE = "/run/secrets/cloudflareToken";
      networks = [ podCfg.networks.proxy.ref ];
    };
    serviceConfig = {
      Restart = "on-failure";
      MemoryHigh = "192M";
      MemoryMax = "256M";
    };
  };
}
