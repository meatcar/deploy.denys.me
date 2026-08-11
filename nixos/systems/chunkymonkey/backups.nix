# Curated restic backup paths for chunkymonkey.
# Excludes the podman image graph (overlay layers) the same way the previous
# config excluded /persist/docker/overlay2.
# DB dumps land in /persist/dumps and are refreshed synchronously by
# backupPrepareCommand below, immediately before the snapshot is taken.
# (The pg-dump@ timers in larapaper.nix still run on their own schedule as a
# safety net, but the backup no longer depends on that ordering.)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  persistPath = config.mine.persistPath;
  # Rootless podman named-volume _data path under the pod home.
  # Verify after first deploy: runuser -u pod -- podman volume inspect larapaper-storage --format '{{.Mountpoint}}'
  volumeData = name: "${persistPath}/pod/.local/share/containers/storage/volumes/${name}/_data";
  larapaperStorageData = volumeData "larapaper-storage";
  invoiceninjaStorageData = volumeData "invoiceninja-storage";
in
{
  services.restic.backups.persist = {
    # Refresh the DB dump synchronously *before* the snapshot. Previously the
    # pg-dump@ timer fired after restic (restic at 00:00, dump at 00:00+30min
    # jitter), so every snapshot captured a dump up to 24h stale.
    # The dump units live in the rootless `pod` user's systemd manager;
    # --machine=pod@.host lets this root-run prepare step drive them, and
    # --wait blocks until the oneshot finishes. This is deliberately
    # fail-closed: a failing dump fails the backup rather than silently
    # snapshotting a stale dump. Failure alerting lands in the SES milestone,
    # which must precede go-live.
    backupPrepareCommand = ''
      #!${pkgs.runtimeShell}
      set -eu
      ${pkgs.systemd}/bin/systemctl --machine=pod@.host --user start --wait pg-dump@larapaper.service
      ${pkgs.systemd}/bin/systemctl --machine=pod@.host --user start --wait mysql-dump@invoiceninja.service
    '';
    # The VPS shares this restic repository and runs at the module default
    # (OnCalendar=daily, i.e. 00:00 with no jitter), so overlapping runs would
    # contend on the repository lock. Stagger chunkymonkey to 02:00-02:30.
    # Note: defining timerConfig replaces the module default wholesale, so
    # Persistent has to be restated here to keep catch-up after downtime.
    timerConfig = {
      OnCalendar = "02:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    # Note the asymmetry: databases are captured as logical dumps, never as raw
    # data directories. The postgres-data / invoiceninja-mysql volumes are
    # deliberately absent, because a file-level copy of a live datadir restores
    # to a torn, possibly unusable state.
    paths = lib.mkForce [
      "${persistPath}/dumps" # pg_dump + mysqldump output, refreshed by backupPrepareCommand
      larapaperStorageData # generated TRMNL screen images (regenerated; best-effort)
      invoiceninjaStorageData # uploaded documents, logos, generated PDFs: NOT regenerable
      "${persistPath}/transit-dashboard/tailscale" # node identity; restoring it avoids re-authentication
      "${persistPath}/traefik" # acme.json (LE certificates)
    ];
    # Exclude everything else under the pod home (podman image graph is large).
    exclude = [
      "${persistPath}/pod/.local/share/containers/storage/overlay*"
      "${persistPath}/pod/.local/share/containers/storage/cache"
      "${persistPath}/pod/.local/share/containers/storage/tmp"
    ];
    # Verify repository integrity, including a sampled read of real pack data.
    # Structure-only checks pass happily over bitrot in the data blobs.
    # Setting checkOpts enables the check run (runCheck defaults on when set).
    checkOpts = [
      "--with-cache" # reuse RESTIC_CACHE_DIR instead of refetching metadata every run
      "--read-data-subset=5%"
    ];
  };

  # The restic module exposes no timeout knob and the generated unit inherits
  # TimeoutStartSec=infinity, so a stalled repository lock or hung network I/O
  # would wedge the unit until the next reboot. Bound the whole run: prepare
  # dump -> backup -> unlock -> forget/prune -> check.
  systemd.services.restic-backups-persist.serviceConfig.TimeoutStartSec = "4h";
}
