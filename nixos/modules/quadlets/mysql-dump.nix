# Reusable MySQL dump template for the pod user's rootless podman session.
# Mirrors pg-dump.nix: systemd user service template mysql-dump@<instance>.
#
# Unlike postgres, which is one shared instance here, each MySQL app owns a
# dedicated server. The instance name is therefore both the database name and
# the container name suffix: mysql-dump@invoiceninja dumps database
# `invoiceninja` out of container `invoiceninja-mysql`.
#
# Dumps land in ${persistPath}/dumps/<instance>.sql alongside the pg_dump
# output, which is the directory restic backs up from chunkymonkey/backups.nix.
{ config, pkgs, ... }:
let
  persistPath = config.mine.persistPath;
  dumpsDir = "${persistPath}/dumps";
in
{
  # Dumps directory owned by pod so the user service can write to it.
  # Declared in pg-dump.nix too; tmpfiles rules are idempotent and identical.
  systemd.tmpfiles.rules = [
    "d ${dumpsDir} 0750 pod pod - -"
  ];

  home-manager.users.pod.systemd.user = {
    services."mysql-dump@" = {
      Unit.Description = "MySQL dump for %i";
      Unit.After = [ "%i-mysql.service" ];
      Service = {
        Type = "oneshot";
        # Units here inherit TimeoutStartSec=infinity, so a wedged mysqldump or
        # `podman exec` would hang forever. restic's backupPrepareCommand blocks
        # on this unit, so an unbounded dump would stall the backup too.
        TimeoutStartSec = "15m";
        # %i only expands in unit directives, never inside a referenced script
        # body, so pass it to dumpScript as $1.
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
