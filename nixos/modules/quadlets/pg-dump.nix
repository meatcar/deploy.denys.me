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
        # %i (systemd specifier) only expands in unit directives, never inside a
        # referenced script body, so pass it to dumpScript as $1.
        ExecStart =
          let
            dumpScript = pkgs.writeShellScript "pg-dump-instance" ''
              set -euo pipefail
              db="$1"
              ${pkgs.coreutils}/bin/mkdir -p "${dumpsDir}"
              # Dump to a temp file and atomically move on success so a failed
              # dump can't clobber the previous good backup with an empty file.
              tmp="${dumpsDir}/$db.sql.tmp"
              ${pkgs.podman}/bin/podman exec postgres \
                pg_dump -U postgres "$db" > "$tmp"
              ${pkgs.coreutils}/bin/mv -f "$tmp" "${dumpsDir}/$db.sql"
            '';
          in
          "${dumpScript} %i";
      };
    };
  };
}
