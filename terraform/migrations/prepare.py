"""Prepare local state consolidation with OpenTofu; never access a backend."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SOURCES = {
    "bao": "module.bao_support.",
    "netbird": "module.netbird_access.",
    "railway": "module.railway_services.",
    "ovh-vps": "",
}


def tofu(directory, *arguments):
    result = subprocess.run(
        ["tofu", *arguments],
        cwd=directory,
        env={
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("TF_", "TG_"))
        },
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ValueError(
            "OpenTofu state command failed; original snapshots remain unchanged."
        )
    return result.stdout.splitlines()


def prepare(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination.exists():
        raise FileExistsError(destination)
    snapshots = {name: source / f"{name}.tfstate" for name in ("main", *SOURCES)}
    lineages = [json.loads(path.read_text())["lineage"] for path in snapshots.values()]
    if len(set(lineages)) != len(lineages) or not all(lineages):
        raise ValueError("Each snapshot must have a distinct, nonempty lineage.")

    with tempfile.TemporaryDirectory() as scratch:
        existing = set(tofu(scratch, "state", "list", f"-state={snapshots['main']}"))
        moves = []
        for name, prefix in SOURCES.items():
            addresses = tofu(scratch, "state", "list", f"-state={snapshots[name]}")
            if not addresses:
                raise ValueError(
                    f"Snapshot {name} has no resources; verify the migration source."
                )
            for address in addresses:
                target = prefix + address
                if target in existing:
                    raise ValueError(f"Destination address collision: {target}")
                existing.add(target)
                moves.append((name, address, target))

        destination.mkdir(mode=0o700)
        previous_umask = os.umask(0o077)
        try:
            for name, path in snapshots.items():
                shutil.copyfile(path, destination / f"{name}.tfstate")
            for name, address, target in moves:
                tofu(
                    scratch,
                    "state",
                    "mv",
                    f"-state={destination / f'{name}.tfstate'}",
                    f"-state-out={destination / 'main.tfstate'}",
                    address,
                    target,
                )
            actual = set(
                tofu(scratch, "state", "list", f"-state={destination / 'main.tfstate'}")
            )
            if actual != existing:
                raise ValueError(
                    "Candidate addresses differ from the migration inventory."
                )
            for name in SOURCES:
                if tofu(
                    scratch,
                    "state",
                    "list",
                    f"-state={destination / f'{name}.tfstate'}",
                ):
                    raise ValueError(f"Source {name} was not fully transferred.")
        finally:
            os.umask(previous_umask)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshots", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    try:
        prepare(arguments.snapshots, arguments.destination)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(
            1, f"Preparation failed: {error}\nDo not publish an incomplete candidate.\n"
        )
    print("Local candidate prepared. No remote state or infrastructure was changed.")
