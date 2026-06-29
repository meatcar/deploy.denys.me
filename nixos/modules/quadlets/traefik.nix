# Rootless Traefik reverse proxy via Podman Quadlet.
# Traefik discovers containers via the pod user's rootless podman API socket,
# presented as a docker-compatible socket at /var/run/docker.sock inside the
# container. Listens on high ports (8080/8443); DNAT in default.nix redirects
# public 80/443 to these.
{ config, pkgs, ... }:
let
  persistDir = "${config.mine.persistPath}/traefik";
  podUid = config.users.users.pod.uid;
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
    providers:
      docker:
        exposedByDefault: false
        network: proxy
    certificatesResolvers:
      le:
        acme:
          email: ${config.mine.notificationEmail}
          storage: /acme.json
          tlsChallenge: {}
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
      ];
      volumes = [
        # Pod user's rootless API socket, presented as the docker socket.
        # podman.socket (user unit) must be active; see unitConfig below.
        "/run/user/${toString podUid}/podman/podman.sock:/var/run/docker.sock:ro"
        "${traefikConfig}:/etc/traefik/traefik.yml:ro"
        "${persistDir}/acme.json:/acme.json"
      ];
      networks = [
        config.home-manager.users.pod.virtualisation.quadlet.networks.proxy.ref
      ];
    };
    unitConfig = {
      # Require the podman API *service* (not just the socket) so traefik's
      # docker provider can discover containers at startup without a race.
      After = [ "podman.service" ];
      Requires = [ "podman.service" ];
    };
    serviceConfig.Restart = "on-failure";
  };
}
