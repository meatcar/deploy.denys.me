# Curated restic backup paths for chunkymonkey.
# Excludes the podman image graph (overlay layers) the same way the previous
# config excluded /persist/docker/overlay2.
# DB dumps are produced by the pg-dump@larapaper user timer (see larapaper.nix)
# before each restic run via the timer schedule; the dump lands in /persist/dumps.
{ config, lib, ... }:
let
  persistPath = config.mine.persistPath;
  # Rootless podman named-volume _data path under the pod home.
  # Verify after first deploy: runuser -u pod -- podman volume inspect larapaper-storage --format '{{.Mountpoint}}'
  larapaperStorageData = "${persistPath}/pod/.local/share/containers/storage/volumes/larapaper-storage/_data";
in
{
  services.restic.backups.persist = {
    paths = lib.mkForce [
      "${persistPath}/dumps" # pg_dump outputs from pg-dump@ user timers
      larapaperStorageData # generated TRMNL screen images (regenerated; best-effort)
      "${persistPath}/traefik" # acme.json (LE certificates)
    ];
    # Exclude everything else under the pod home (podman image graph is large).
    exclude = [
      "${persistPath}/pod/.local/share/containers/storage/overlay*"
      "${persistPath}/pod/.local/share/containers/storage/cache"
      "${persistPath}/pod/.local/share/containers/storage/tmp"
    ];
  };
}
