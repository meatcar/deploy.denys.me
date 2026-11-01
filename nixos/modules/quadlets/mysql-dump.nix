# NOTE: Each MySQL app owns its server: mysql-dump@<db> dumps <db> from container <db>-mysql.
{ config, pkgs, ... }:
let
  persistPath = config.mine.persistPath;
  dumpsDir = "${persistPath}/dumps";
in
{
  # NOTE: Also declared in pg-dump.nix; identical tmpfiles rules are idempotent.
  systemd.tmpfiles.rules = [
    "d ${dumpsDir} 0750 pod pod - -"
  ];

  home-manager.users.pod.systemd.user = {
    services."mysql-dump@" = {
      Unit.Description = "MySQL dump for %i";
      Unit.After = [ "%i-mysql.service" ];
      Service = {
        Type = "oneshot";
        # NOTE: Default is TimeoutStartSec=infinity, and restic backupPrepareCommand blocks on this unit.
        TimeoutStartSec = "15m";
        # NOTE: %i expands only in unit directives, not in the script body.
        ExecStart =
          let
            dumpScript = pkgs.writeShellScript "mysql-dump-instance" ''
              set -euo pipefail
              db="$1"
              # Ensure the dumps dir exists *before* tightening the umask, so a
              # directory created here keeps the 0750 mode declared in
              # systemd.tmpfiles instead of being narrowed to 0700.
              ${pkgs.coreutils}/bin/mkdir -p "${dumpsDir}"
              # Dumps are full plaintext copies of the database, so keep the
              # dump files themselves owner-only (0600) rather than 0644.
              umask 077

              # Read the root password into the environment rather than passing
              # it on the command line, where it would be visible in `ps` and
              # trigger mysqldump's insecure-password warning.
              MYSQL_PWD=$(${pkgs.coreutils}/bin/cat ${config.age.secrets.mysqlRootPass.path})
              export MYSQL_PWD

              # Dump to a temp file and atomically move on success so a failed
              # dump can't clobber the previous good backup with an empty file.
              # mv preserves the temp file's restrictive mode.
              tmp="${dumpsDir}/$db.sql.tmp"
              # Drop a partial dump if we fail or get killed (e.g. on timeout).
              # Absolute path: this user service runs with an empty PATH.
              trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT

              # --single-transaction: consistent InnoDB snapshot without locking
              #   out the running app.
              # --routines/--triggers/--events: schema objects mysqldump would
              #   otherwise silently omit, leaving an incomplete restore.
              # --databases: emit CREATE DATABASE + USE so a restore can rebuild
              #   the database from nothing.
              ${pkgs.podman}/bin/podman exec -e MYSQL_PWD "$db-mysql" \
                mysqldump --user=root \
                  --single-transaction \
                  --routines --triggers --events \
                  --databases "$db" > "$tmp"

              ${pkgs.coreutils}/bin/mv -f "$tmp" "${dumpsDir}/$db.sql"
              # Temp file is gone (renamed), so stop the trap from firing.
              trap - EXIT
            '';
          in
          "${dumpScript} %i";
      };
    };
  };
}
