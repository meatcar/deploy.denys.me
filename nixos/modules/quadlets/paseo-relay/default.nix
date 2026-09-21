{ config, pkgs, ... }:
let
  revision = "a2f2573c3ab1e9cfe3260f916d5ef31ea454ad63";
  source = pkgs.fetchFromGitHub {
    owner = "meatcar";
    repo = "paseo-relay";
    rev = revision;
    hash = "sha256-9BAp1gXlG6gIRxjZDR83IH/YOoMvCY20g928xL7bb3w=";
  };
  quadlet = config.home-manager.users.pod.virtualisation.quadlet;
  routes = pkgs.writeText "paseo-relay-routes.yml" (
    builtins.toJSON {
      http = {
        routers.paseo-relay = {
          rule = "Host(`paseo.denys.me`)";
          entryPoints = [ "websecure" ];
          service = "paseo-relay";
          tls.certResolver = "le-dns";
        };
        services.paseo-relay.loadBalancer.servers = [ { url = "http://paseo-relay:4000"; } ];
      };
    }
  );
in
{
  home-manager.users.pod.virtualisation.quadlet = {
    networks.paseo-relay.networkConfig.name = "paseo-relay";
    builds.paseo-relay = {
      buildConfig = {
        tag = "localhost/paseo-relay:${revision}";
        workdir = "${source}";
        file = "${source}/Dockerfile";
      };
      serviceConfig.TimeoutStartSec = "15min";
    };
    containers.traefik.containerConfig = {
      networks = [ quadlet.networks.paseo-relay.ref ];
      volumes = [ "${routes}:/etc/traefik/dynamic/paseo-relay.yml:ro" ];
    };
    containers.paseo-relay = {
      autoStart = true;
      containerConfig = {
        image = quadlet.builds.paseo-relay.ref;
        name = "paseo-relay";
        networks = [ quadlet.networks.paseo-relay.ref ];
        environments = {
          ELIXIR_ERL_OPTIONS = "+fnu +S 1:1";
          PASEO_RELAY_HOST = "0.0.0.0";
          PASEO_RELAY_PORT = "4000";
          PASEO_RELAY_MIN_CLUSTER_SIZE = "1";
          PASEO_RELAY_ACCEPTORS = "10";
          PASEO_RELAY_CONNECTIONS_PER_ACCEPTOR = "100";
          PASEO_RELAY_MEMORY_WATERMARK_BYTES = "1610612736";
        };
        dropCapabilities = [ "all" ];
        noNewPrivileges = true;
        readOnly = true;
        tmpfses = [ "/tmp" ];
      };
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
        CPUQuota = "100%";
        MemoryHigh = "1536M";
        MemoryMax = "2G";
        LimitNOFILE = 65536;
      };
    };
  };
}
