import argparse
import json
import os
import secrets
import string
import subprocess
import sys

from cli_proxy_api.deployment import Deployment


class Bao:
    def __init__(self, mount):
        self.mount = mount

    def read(self, path):
        endpoint = self.mount + "/data/" + path
        result = subprocess.run(
            ["bao", "read", "-format=json", endpoint],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode:
            if result.stderr.strip() == "No value found at " + endpoint:
                return None, 0
            raise RuntimeError("Bao read failed")
        data = json.loads(result.stdout)["data"]
        if data["data"] is None:
            raise RuntimeError("Restore the deleted secret before rotating")
        return data["data"], data["metadata"]["version"]

    def write(self, path, value, version):
        subprocess.run(
            ["bao", "write", "-format=json", self.mount + "/data/" + path, "-"],
            input=json.dumps({"options": {"cas": version}, "data": value}),
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )


def rotate(generation, bao, host, *, secret_path, base_url):
    current, version = bao.read(secret_path)
    pending, pending_version = bao.read(secret_path + "-pending")
    if pending is None or pending["secret"]["generation"] != generation:
        if pending is not None and current != pending["secret"]:
            raise ValueError("Finish the pending generation first")
        if generation != (current["generation"] + 1 if current else 1):
            raise ValueError("Use the next consecutive generation, or retry the pending one")
        if current is not None:
            host("stage", current)
            host("apply")
            host("commit", {"generation": current["generation"]})
        pending = {
            "published_version": version,
            "secret": {
                "generation": generation,
                "admin_key": "".join(
                    secrets.choice(string.ascii_letters + string.digits) for _ in range(48)
                ),
                "base_url": base_url,
            },
        }
        bao.write(secret_path + "-pending", pending, pending_version)
        pending, pending_version = bao.read(secret_path + "-pending")
    target = pending["secret"]
    if target["generation"] != generation:
        raise ValueError("Another rotation replaced the candidate")
    if target["base_url"] != base_url:
        raise ValueError("Retry with the pending generation's management endpoint")
    if current != target and version != pending["published_version"]:
        raise ValueError("Published secret changed outside this operation")
    host("stage", target)
    host("apply")
    host("verify")
    if bao.read(secret_path + "-pending") != (pending, pending_version):
        raise ValueError("Candidate changed during deployment")
    current, version = bao.read(secret_path)
    if current != target:
        if version != pending["published_version"]:
            raise ValueError("Published secret changed during deployment")
        bao.write(secret_path, target, version)
    if bao.read(secret_path)[0] != target:
        raise ValueError("Published credential differs from the verified candidate")
    host("commit", {"generation": generation})


def main():
    parser = argparse.ArgumentParser(
        description="Rotate or resume a Manager Plus admin-key generation"
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("CLI_PROXY_API_CONFIG"),
        required=not os.environ.get("CLI_PROXY_API_CONFIG"),
    )
    parser.add_argument("generation", type=int)
    args = parser.parse_args()
    try:
        if args.generation < 1:
            raise ValueError("Generation must be positive")
        deployment = Deployment.load(args.config)
        rotate(
            args.generation,
            Bao(deployment.secret_mount),
            deployment.rotate_admin,
            secret_path=deployment.admin_secret_path,
            base_url=deployment.management_url,
        )
        print(f"Admin generation {args.generation} verified and published in OpenBao.")
    except Exception as error:
        print(
            f"Admin rotation incomplete ({type(error).__name__}). Retry generation {args.generation}; do not increment it.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
