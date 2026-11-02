import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path

from .bao import Bao
from .sync import run


def main(argv=None):
    parser = argparse.ArgumentParser(prog="bao-sync")
    parser.add_argument("mode", choices=["plan", "apply"])
    parser.add_argument("--force", action="store_true", help="ignore the change gate")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    token = Path(os.environ["BAO_SYNC_TOKEN_FILE"]).read_text().strip()
    state_path = Path(os.environ.get("STATE_DIRECTORY", ".")) / "state.json"
    state = _load(state_path)
    bao = Bao(os.environ.get("BAO_ADDR", "https://bao.vpn.denys.me"), token)
    now = time.time()
    _keep_token_alive(bao, state, now)
    errors = run(bao, state, now, apply=args.mode == "apply", force=args.force)
    if args.mode == "apply":
        _save(state_path, state)
    return 1 if errors else 0


def _keep_token_alive(bao, state, now):
    """Renew at half the period. Lookups and renewals are audited; skip them in between."""
    if now < state.get("token_check_at", 0):
        return
    lookup = bao.lookup()
    period = lookup.get("period") or 0
    if not period:
        sys.exit("bao-sync: token must be periodic")
    ttl = lookup["ttl"]
    if ttl < period / 2:
        bao.renew()
        ttl = period
    state["token_check_at"] = now + ttl - period / 2


def _load(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except ValueError:
        logging.warning("state %s unreadable; starting fresh", path)
        return {}


def _save(path, state):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as file:
        json.dump(state, file, sort_keys=True)
        file.flush()
        os.fsync(file.fileno())
    temporary.replace(path)


def entrypoint():
    sys.exit(main())
