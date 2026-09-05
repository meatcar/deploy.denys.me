import argparse
import os
import sqlite3
import sys
import tarfile
import tempfile
from contextlib import closing
from pathlib import Path

from cli_proxy_api.admin import lock


def snapshot(state, destination):
    state = state.resolve()
    destination = destination.resolve()
    if destination.is_relative_to(state):
        raise ValueError("Backup destination must be outside application state")
    database = "manager/usage.sqlite"
    excluded = {
        database,
        database + "-wal",
        database + "-shm",
        database + "-journal",
        "admin-rotation.lock",
        "admin-recovery.lock",
    }
    with lock(state / "admin-rotation.lock"), lock(state / "admin-recovery.lock"):
        for required in ("manager/admin-key", "manager/data.key"):
            if not (state / required).is_file():
                raise FileNotFoundError("Manager credentials are incomplete")
        with tempfile.TemporaryDirectory(prefix=".cli-proxy-api-", dir=destination.parent) as work:
            work = Path(work)
            with (
                closing(
                    sqlite3.connect((state / database).as_uri() + "?mode=ro", uri=True)
                ) as source,
                closing(sqlite3.connect(work / "usage.sqlite")) as target,
            ):
                source.backup(target)
                target.execute("PRAGMA journal_mode=DELETE")
            archive_path = work / "backup.tar"
            with tarfile.open(archive_path, "w") as archive:
                for path in sorted(state.iterdir()):
                    archive.add(
                        path,
                        arcname=path.name,
                        filter=lambda member: None if member.name in excluded else member,
                    )
                archive.add(work / "usage.sqlite", arcname=database)
            os.chmod(archive_path, 0o600)
            with archive_path.open("rb") as file:
                os.fsync(file.fileno())
            os.replace(archive_path, destination)
            directory = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)


def main():
    parser = argparse.ArgumentParser(description="Snapshot CLIProxyAPI state for backup")
    parser.add_argument("state", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        snapshot(args.state, args.destination)
    except Exception as error:
        print(f"CLIProxyAPI backup failed ({type(error).__name__}).", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
