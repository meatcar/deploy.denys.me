# Reusable PostgreSQL dump template for the pod user's rootless podman session.
# Defines a systemd user service+timer template pg-dump@<db>.
# Each DB-backed service instantiates the timer (e.g. pg-dump@larapaper.timer)
# in its own module file. Dumps land in ${persistPath}/dumps/<db>.sql,
# which restic backs up from chunkymonkey/backups.nix.
{ config, pkgs, ... }:
let
  persistPath = config.mine.persistPath;
  dumpsDir = "${persistPath}/dumps";
in
{
  # Dumps directory owned by pod so the user service can write to it.
  systemd.tmpfiles.rules = [
    "d ${dumpsDir} 0750 pod pod - -"
  ];

  home-manager.users.pod.systemd.user = {
    # Template service: instantiate with pg-dump@<db>.
    # %i is the database name; pg_dump runs in the shared `postgres` container
    # (app and DB are separate containers, so %i is NOT a container name).
    services."pg-dump@" = {
      Unit.Description = "PostgreSQL dump for %i";
      Unit.After = [ "postgres.service" ];
      Service = {
        Type = "oneshot";
        # Units here inherit TimeoutStartSec=infinity, so a wedged pg_dump or
        # `podman exec` would hang forever. restic's backupPrepareCommand blocks
        # on this unit, so an unbounded dump would stall the backup too.
        TimeoutStartSec = "15m";
        # %i (systemd specifier) only expands in unit directives, never inside a
        # referenced script body, so pass it to dumpScript as $1.
        ExecStart =
          let
            dumpScript = pkgs.writeShellScript "pg-dump-instance" ''
              set -euo pipefail
              db="$1"
              # Ensure the dumps dir exists *before* tightening the umask, so a
              # directory created here keeps the 0750 mode declared in
              # systemd.tmpfiles instead of being narrowed to 0700.
              ${pkgs.coreutils}/bin/mkdir -p "${dumpsDir}"
              # Dumps are full plaintext copies of the database, so keep the
              # dump files themselves owner-only (0600) rather than 0644.
              umask 077
              # Dump to a temp file and atomically move on success so a failed
              # dump can't clobber the previous good backup with an empty file.
              # mv preserves the temp file's restrictive mode.
              tmp="${dumpsDir}/$db.sql.tmp"
              # Drop a partial dump if we fail or get killed (e.g. on timeout).
              # Absolute path: this user service runs with an empty PATH.
              trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
              ${pkgs.podman}/bin/podman exec postgres \
                pg_dump -U postgres "$db" > "$tmp"
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
