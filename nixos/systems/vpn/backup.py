import os
from pathlib import Path
import shutil
import subprocess
import urllib.request


def main():
    os.umask(0o077)
    destination = Path("/var/lib/vpn/backup")
    role = Path("/etc/vpn/role").read_text().strip()
    if role == "bao":
        snapshot_bao(destination)
    elif role == "vpn":
        snapshot_netbird(destination)
    else:
        raise ValueError("Unknown backup role")


def snapshot_bao(destination):
    token = Path("/etc/vpn/bao-backup-token").read_text().strip()
    headers = {"X-Vault-Token": token}
    base = "https://bao.vpn.denys.me/v1"
    renewal = urllib.request.Request(
        base + "/auth/token/renew-self", data=b"{}", headers=headers, method="POST"
    )
    with urllib.request.urlopen(renewal, timeout=30):
        pass
    request = urllib.request.Request(
        base + "/sys/storage/raft/snapshot", headers=headers
    )
    temporary = destination / "openbao.snap.tmp"
    with (
        urllib.request.urlopen(request, timeout=300) as response,
        temporary.open("wb") as target,
    ):
        shutil.copyfileobj(response, target)
    temporary.replace(destination / "openbao.snap")


def snapshot_netbird(destination):
    subprocess.run(["systemctl", "stop", "podman-netbird-server.service"], check=True)
    try:
        pending = destination / "netbird.pending"
        if pending.exists():
            shutil.rmtree(pending)
        shutil.copytree("/var/lib/vpn/server", pending)
        if (destination / "netbird").exists():
            shutil.rmtree(destination / "netbird")
        pending.rename(destination / "netbird")
    finally:
        subprocess.run(
            ["systemctl", "start", "podman-netbird-server.service"], check=True
        )


if __name__ == "__main__":
    main()
