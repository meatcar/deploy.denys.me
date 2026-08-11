# Shared rootless Postgres instance via Podman Quadlet.
# Uses a podman named volume (postgres-data) so userns ownership is handled
# automatically — no uid 70 chown gymnastics.
# DB is NOT published on the host loopback; provisioning and dumps are done
# via `podman exec postgres ...` from user services in the pod session.
#
# Per-app role+DB provisioning: add an initdb quadlet container in
# the consuming service module (see larapaper.nix for the pattern).
{ config, ... }:
let
  pgversion = "18";
in
{
  home-manager.users.pod.virtualisation.quadlet = {
    volumes.postgres-data.volumeConfig = { }; # plain named volume, podman manages ownership

    containers.postgres = {
      autoStart = true;
      containerConfig = {
        image = "postgres:${pgversion}.4-alpine";
        volumes = [
          "${config.home-manager.users.pod.virtualisation.quadlet.volumes.postgres-data.ref}:/var/lib/postgresql"
          # Mount the secret file so POSTGRES_PASSWORD_FILE can reference it.
          "${config.age.secrets.postgresPass.path}:${config.age.secrets.postgresPass.path}:ro"
        ];
        environments = {
          POSTGRES_PASSWORD_FILE = config.age.secrets.postgresPass.path;
        };
        networks = [
          config.home-manager.users.pod.virtualisation.quadlet.networks.postgres.ref
        ];
      };
      serviceConfig = {
        Restart = "on-failure";
        # Steady state sits under 50M; the ceiling is here to stop a runaway
        # query from consuming the host, not to constrain normal use.
        MemoryHigh = "768M";
        MemoryMax = "1G";
      };
    };
  };
}
