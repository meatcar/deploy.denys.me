{
  config,
  lib,
  pkgs,
  ...
}:
let
  persistPath = config.mine.persistPath;
  cliProxyApi = builtins.fromJSON (builtins.readFile config.mine.cliProxyApi.deploymentFile);
  volumeData = name: "${persistPath}/pod/.local/share/containers/storage/volumes/${name}/_data";
  larapaperStorageData = volumeData "larapaper-storage";
  invoiceninjaStorageData = volumeData "invoiceninja-storage";
in
{
  mine.cliProxyApi.backupFile = "${persistPath}/dumps/cli-proxy-api.tar";

  services.restic.backups.persist = {
    # NOTE: Fail-closed: a failed dump fails the backup instead of snapshotting a stale dump.
    backupPrepareCommand = ''
      #!${pkgs.runtimeShell}
      set -eu
      ${pkgs.systemd}/bin/systemctl --machine=pod@.host --user start --wait pg-dump@larapaper.service
      ${pkgs.systemd}/bin/systemctl --machine=pod@.host --user start --wait mysql-dump@invoiceninja.service
      ${pkgs.systemd}/bin/systemctl --machine=${lib.escapeShellArg "${cliProxyApi.service_user}@.host"} --user start --wait cli-proxy-api-backup.service
      ${pkgs.systemd}/bin/systemctl --machine=pod@.host --user start --wait silverbullet-backup.service
    '';
    # NOTE: The VPS shares this repository at 00:00; stagger to avoid lock contention. timerConfig replaces the default, so restate Persistent.
    timerConfig = {
      OnCalendar = "02:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    # NOTE: Databases only as logical dumps; a file copy of a live datadir restores torn.
    paths = lib.mkForce [
      "${persistPath}/dumps"
      larapaperStorageData # regenerated; best-effort
      invoiceninjaStorageData # not regenerable
      "${persistPath}/transit-dashboard/tailscale" # node identity
      "/var/lib/netbird-default" # node identity; restore avoids re-enrollment
      "${persistPath}/traefik"
    ];
    exclude = [
      "${persistPath}/dumps/.cli-proxy-api-*"
      "${persistPath}/dumps/.silverbullet-*"
      "${persistPath}/pod/.local/share/containers/storage/overlay*"
      "${persistPath}/pod/.local/share/containers/storage/cache"
      "${persistPath}/pod/.local/share/containers/storage/tmp"
    ];
    # NOTE: Setting checkOpts enables the check run. --read-data-subset detects data-blob bitrot.
    checkOpts = [
      "--with-cache"
      "--read-data-subset=5%"
    ];
  };

  # NOTE: The restic module has no timeout option; the unit default is TimeoutStartSec=infinity.
  systemd.services.restic-backups-persist.serviceConfig.TimeoutStartSec = "4h";
}
