import argparse
import copy
import json
import os
import secrets
from pathlib import Path


def initialize(path, settings):
    manager_dir = path.parent / "manager"
    manager_dir.mkdir(mode=0o700, exist_ok=True)
    try:
        fd = os.open(manager_dir / "admin-key", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "w") as file:
            file.write("cpamp_" + secrets.token_hex(32) + "\n")
    if path.exists():
        return
    key_path = path.with_name("management-key")
    try:
        fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        management_key = key_path.read_text().strip()
        if not management_key:
            raise ValueError("management-key is empty; restore it before starting")
    else:
        management_key = secrets.token_urlsafe(32)
        with os.fdopen(fd, "w") as file:
            file.write(management_key + "\n")
    config = copy.deepcopy(settings)
    config["api-keys"] = [secrets.token_urlsafe(32)]
    config.setdefault("remote-management", {})["secret-key"] = management_key
    pending = path.with_name("config.pending")
    fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump(config, file, indent=2)
        file.write("\n")
    os.replace(pending, path)


def main():
    parser = argparse.ArgumentParser(description="Initialize missing CLIProxyAPI state")
    parser.add_argument("config", type=Path)
    parser.add_argument("--settings", type=Path, required=True)
    args = parser.parse_args()
    initialize(args.config, json.loads(args.settings.read_text()))


if __name__ == "__main__":
    main()
