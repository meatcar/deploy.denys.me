{ config, pkgs, ... }:
let
  persistPath = config.mine.persistPath;
  dumpsDir = "${persistPath}/dumps";
in
{
  systemd.tmpfiles.rules = [
    "d ${dumpsDir} 0750 pod pod - -"
  ];

  home-manager.users.pod.systemd.user = {
    # NOTE: %i is the database name, not a container; all databases share the `postgres` container.
    services."pg-dump@" = {
      Unit.Description = "PostgreSQL dump for %i";
      Unit.After = [ "postgres.service" ];
      Service = {
        Type = "oneshot";
        # NOTE: Default is TimeoutStartSec=infinity, and restic backupPrepareCommand blocks on this unit.
        TimeoutStartSec = "15m";
        # NOTE: %i expands only in unit directives, not in the script body.
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
