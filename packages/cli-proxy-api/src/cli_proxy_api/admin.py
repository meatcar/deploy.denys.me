import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path


@contextmanager
def lock(path):
    with path.open("a") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        yield


def replace(path, text):
    temporary = path.with_suffix(".next")
    with temporary.open("w") as file:
        os.chmod(temporary, 0o600)
        file.write(text)
        file.flush()
        os.fsync(file.fileno())
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def status(args, key):
    result = subprocess.run(
        [
            "curl",
            "--silent",
            "--output",
            "/dev/null",
            "--write-out",
            "%{http_code}",
            "--connect-timeout",
            "2",
            "--max-time",
            "5",
            "--noproxy",
            "*",
            *(["--connect-to", args.connect_to] if args.connect_to else []),
            "--header",
            "@-",
            args.url + "/status",
        ],
        input="Authorization: Bearer " + key + "\n",
        text=True,
        capture_output=True,
    )
    return result.stdout if result.returncode == 0 else "unavailable"


def verify(args, journal):
    for _ in range(40):
        if status(args, journal["admin_key"]) == "200":
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("Target credential is not active")
    previous = journal.get("previous_key")
    if previous and status(args, previous) not in ("401", "403"):
        raise RuntimeError("Previous credential was not rejected")
    if (args.state / "manager/admin-key").read_text().strip() != journal["admin_key"]:
        raise RuntimeError("Credential file differs from the operation")


def execute():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--connect-to")
    parser.add_argument("action", choices=["stage", "recover", "reconcile", "verify", "commit"])
    args = parser.parse_args()
    journal_path = args.state / "admin-rotation.json"
    key_path = args.state / "manager/admin-key"

    # NOTE: ExecStartPre must not take the lock held by its restarting worker.
    lock_name = "admin-recovery.lock" if args.action == "recover" else "admin-rotation.lock"
    with lock(args.state / lock_name):
        journal = json.loads(journal_path.read_text()) if journal_path.exists() else None
        if args.action == "recover":
            if journal is None:
                return
            if not (args.state / "manager/usage.sqlite").is_file():
                raise RuntimeError("Restore the existing database before recovery")
            replace(key_path, journal["admin_key"] + "\n")
            run(
                "podman",
                "run",
                "--rm",
                "--network",
                "none",
                "--pull",
                "never",
                "--cap-drop",
                "all",
                "--security-opt",
                "no-new-privileges",
                "--volume",
                str(args.state / "manager") + ":/data",
                args.image,
                "reset-admin-key",
                "--db-path",
                "/data/usage.sqlite",
                "--admin-key-file",
                "/data/admin-key",
                timeout=60,
            )
            return

        if args.action == "stage":
            candidate = json.load(sys.stdin)
            generation = candidate["generation"]
            key = candidate["admin_key"]
            if (
                type(generation) is not int
                or generation < 1
                or not re.fullmatch(r"[A-Za-z0-9]{48}", key)
            ):
                raise ValueError("Invalid candidate")
            if journal and generation == journal["generation"]:
                if key != journal["admin_key"]:
                    raise ValueError("Generation already has a different key")
                return
            if generation != (journal["generation"] + 1 if journal else 1):
                raise ValueError("Generations must be consecutive")
            if journal and not journal["published"]:
                raise ValueError("Publish the current operation before starting another")
            previous = key_path.read_text().strip()
            if key == previous or status(args, previous) != "200":
                raise ValueError("Verify the current credential before staging a replacement")
            with lock(args.state / "admin-recovery.lock"):
                replace(
                    journal_path,
                    json.dumps(
                        {
                            "generation": generation,
                            "admin_key": key,
                            "previous_key": previous,
                            "published": False,
                        }
                    )
                    + "\n",
                )
            return

        if journal is None:
            raise ValueError("No staged operation")
        if args.action == "reconcile":
            if (
                status(args, journal["admin_key"]) != "200"
                or key_path.read_text().strip() != journal["admin_key"]
            ):
                run("systemctl", "--user", "restart", args.service, timeout=120)
        verify(args, journal)
        if args.action == "commit":
            if json.load(sys.stdin)["generation"] != journal["generation"]:
                raise ValueError("Cannot acknowledge a different generation")
            journal["published"] = True
            journal.pop("previous_key", None)
            with lock(args.state / "admin-recovery.lock"):
                replace(journal_path, json.dumps(journal) + "\n")


def main():
    try:
        execute()
    except Exception as error:
        print(
            f"Admin maintenance failed ({type(error).__name__}); retry the same generation. No database rollback was performed.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
