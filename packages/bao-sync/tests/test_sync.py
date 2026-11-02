import json
import logging
import os
import time
import urllib.request

import pytest

from bao_sync.bao import Bao
from bao_sync.cli import main
from bao_sync.sync import FULL_INTERVAL, run
from bao_sync.vercel import Vercel

from .conftest import Reject, cli, wait

MOUNT = "projects/acme/webapp"
RECORD = {
    "project": "acme/webapp",
    "amp": {
        "project_id": "7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f",
        "subject": "user:user_x:project:7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f",
    },
    "environments": {
        "dev": {"app": ["public"]},
        "prod": {"app": ["public", "varlock"], "admin": ["sync-vercel"]},
    },
    "amp_grants": [],
    "destinations": {
        "vercel": {
            "type": "vercel",
            "project_id": "prj_abc",
            "team_id": "team_abc",
            "credential": "prod/admin/sync-vercel",
        }
    },
    "syncs": [
        {
            "source": "prod/app/public",
            "destination": "vercel",
            "target": "production",
            "keys": ["NEXT_PUBLIC_A", "NEXT_PUBLIC_B"],
            "redeploy": True,
        },
        {
            "source": "dev/app/public",
            "destination": "vercel",
            "target": "preview",
            "keys": ["NEXT_PUBLIC_A", "NEXT_PUBLIC_B"],
        },
    ],
}


def put(bao, path, data):
    request = urllib.request.Request(
        f"{bao}/v1/{path}",
        data=json.dumps({"data": data}).encode(),
        method="POST",
        headers={"X-Vault-Token": os.environ["BAO_TOKEN"]},
    )
    urllib.request.urlopen(request).close()


class CountingBao(Bao):
    lists = 0

    def versions(self, *args):
        self.lists += 1
        return super().versions(*args)


@pytest.fixture
def world(bao, vercel):
    cli("secrets", "enable", "-path=registry", "kv-v2")
    cli("secrets", "enable", f"-path={MOUNT}", "kv-v2")
    # NOTE: kv-v2 refuses writes until its upgrade finishes after enable.
    wait(lambda: put(bao, "registry/data/webapp", RECORD))
    wait(lambda: put(bao, f"{MOUNT}/data/prod/admin/sync-vercel", {"token": "vercel-test-token"}))
    put(
        bao,
        f"{MOUNT}/data/prod/app/public",
        {"NEXT_PUBLIC_A": "prod-a1", "NEXT_PUBLIC_B": "prod-b1"},
    )
    put(bao, f"{MOUNT}/data/dev/app/public", {"NEXT_PUBLIC_A": "dev-a1", "NEXT_PUBLIC_B": "dev-b1"})
    client = CountingBao(bao, os.environ["BAO_TOKEN"])
    clients = {"vercel": lambda destination, token: Vercel(destination, token, api=vercel.url)}

    def cycle(state, now=0, **options):
        return run(client, state, now, clients=clients, **options)

    cycle.bao = client
    yield bao, vercel, cycle
    cli("secrets", "disable", "registry")
    cli("secrets", "disable", MOUNT)


def by_key_target(vercel):
    return {
        (env["key"], env["target"][0]): (env, vercel.values[env["id"]])
        for env in vercel.envs.values()
    }


def test_plan_writes_nothing_and_leaves_state(world):
    _, vercel, cycle = world
    state = {}
    assert cycle(state, apply=False) == 0
    assert vercel.writes() == [] and state == {}


def test_apply_creates_sensitive_marked_vars_per_target(world, caplog):
    _, vercel, cycle = world
    caplog.set_level(logging.INFO)
    assert cycle({}, apply=True) == 0
    synced = by_key_target(vercel)
    env, value = synced[("NEXT_PUBLIC_A", "production")]
    assert value == "prod-a1" and env["type"] == "sensitive"
    assert env["comment"] == f"bao-sync {MOUNT}/prod/app/public v1"
    assert synced[("NEXT_PUBLIC_B", "preview")][1] == "dev-b1"
    assert len(synced) == 4
    assert not any(secret in caplog.text for secret in ("prod-a1", "dev-b1", "vercel-test-token"))


def test_gate_skips_destinations_until_bao_changes(world):
    bao, vercel, cycle = world
    state = {}
    cycle(state, apply=True)
    assert vercel.redeploys == []
    assert cycle(state, now=60, apply=True) == 0
    assert len(vercel.redeploys) == 1
    calls, lists = len(vercel.calls), cycle.bao.lists
    assert cycle(state, now=120, apply=True) == 0
    assert (len(vercel.calls), cycle.bao.lists) == (calls, lists)

    put(bao, f"{MOUNT}/data/prod/app/varlock", {"_VARLOCK_ENV_KEY": "unsynced"})
    assert cycle(state, now=150, apply=True) == 0
    assert cycle.bao.lists > lists
    assert len(vercel.calls) == calls

    put(
        bao,
        f"{MOUNT}/data/prod/app/public",
        {"NEXT_PUBLIC_A": "prod-a2", "NEXT_PUBLIC_B": "prod-b1"},
    )
    before = len(vercel.writes())
    assert cycle(state, now=180, apply=True) == 0
    synced = by_key_target(vercel)
    assert synced[("NEXT_PUBLIC_A", "production")][1] == "prod-a2"
    assert synced[("NEXT_PUBLIC_A", "preview")][1] == "dev-a1"
    production = sorted(synced[(key, "production")][0]["id"] for key in RECORD["syncs"][0]["keys"])
    assert vercel.writes()[before:] == [
        ("PATCH", f"/v9/projects/prj_abc/env/{env_id}") for env_id in production
    ]
    assert len(vercel.redeploys) == 1

    assert cycle(state, now=240, apply=True) == 0
    assert vercel.redeploys[-1] == {
        "deploymentId": "dpl_current",
        "name": "webapp",
        "target": "production",
        "meta": {"action": "redeploy"},
    }
    assert len(vercel.redeploys) == 2
    assert cycle(state, now=300, apply=True) == 0
    assert len(vercel.redeploys) == 2


def test_dashboard_edit_is_repaired_on_full_reconcile(world):
    _, vercel, cycle = world
    state = {}
    cycle(state, apply=True)
    cycle(state, now=60, apply=True)
    env, _ = by_key_target(vercel)[("NEXT_PUBLIC_B", "preview")]
    env["updatedAt"] += 1
    vercel.values[env["id"]] = "edited"
    assert cycle(state, now=120, apply=True) == 0
    assert vercel.values[env["id"]] == "edited"
    assert cycle(state, now=FULL_INTERVAL, apply=True) == 0
    assert vercel.values[env["id"]] == "dev-b1"


def test_mismatched_fields_write_nothing(world):
    bao, vercel, cycle = world
    put(bao, f"{MOUNT}/data/prod/app/public", {"NEXT_PUBLIC_A": "prod-a1", "EXTRA": "x"})
    assert cycle({}, apply=True) == 1
    assert {target for _, target in by_key_target(vercel)} == {"preview"}


def test_deleted_source_never_deletes_destination(world):
    _, vercel, cycle = world
    state = {}
    cycle(state, apply=True)
    cli("kv", "metadata", "delete", f"-mount={MOUNT}", "prod/app/public")
    assert cycle(state, now=60, apply=True) == 1
    assert len(by_key_target(vercel)) == 4
    assert ("DELETE",) not in {call[:1] for call in vercel.calls}


def test_deleted_registry_record_is_isolated(world):
    bao, vercel, cycle = world
    put(bao, "registry/data/gone", RECORD | {"project": "acme/gone"})
    cli("kv", "delete", "-mount=registry", "gone")
    assert cycle({}, apply=True) == 1
    assert len(by_key_target(vercel)) == 4


def test_invalid_registry_record_is_isolated(world):
    bao, vercel, cycle = world
    put(bao, "registry/data/broken", {"project": "acme/webapp-2", "syncs": [{"source": "x"}]})
    assert cycle({}, apply=True) == 1
    assert len(by_key_target(vercel)) == 4


def test_plan_renews_a_token_past_half_its_period(bao, tmp_path, monkeypatch):
    token = json.loads(cli("token", "create", "-orphan", "-period=4s", "-format=json"))
    token_file = tmp_path / "token"
    token_file.write_text(token["auth"]["client_token"])
    monkeypatch.setenv("BAO_SYNC_TOKEN_FILE", str(token_file))
    monkeypatch.setenv("BAO_ADDR", bao)
    monkeypatch.setenv("STATE_DIRECTORY", str(tmp_path))
    client = Bao(bao, token["auth"]["client_token"])
    while client.lookup()["ttl"] >= 2:
        time.sleep(0.2)
    assert main(["plan"]) == 0
    assert client.lookup()["ttl"] > 2
    assert not (tmp_path / "state.json").exists()


@pytest.mark.parametrize(
    ("status", "retry_after", "retry_at"), [(500, None, 60), (429, "120", 120)]
)
def test_failed_write_is_retried_without_a_bao_change(world, status, retry_after, retry_at):
    _, vercel, cycle = world
    state = {}
    vercel.reject_next_write = Reject(status, retry_after)
    assert cycle(state, apply=True) == 1
    if retry_after:
        calls = len(vercel.calls)
        assert cycle(state, now=retry_at - 1, apply=True) == 0
        assert len(vercel.calls) == calls
    assert cycle(state, now=retry_at, apply=True) == 0
    assert len(by_key_target(vercel)) == 4
    calls = len(vercel.calls)
    assert cycle(state, now=retry_at + 60, apply=True) == 0
    assert cycle(state, now=retry_at + 120, apply=True) == 0
    assert len(vercel.calls) == calls + 3  # redeploy: env list, deployment lookup, redeploy


def unmanaged_preview_a(vercel):
    vercel.envs["env_manual"] = {
        "id": "env_manual",
        "key": "NEXT_PUBLIC_A",
        "type": "encrypted",
        "target": ["preview"],
        "comment": "",
        "updatedAt": 1,
    }
    vercel.values["env_manual"] = "manual"


def test_skipped_key_does_not_block_production_redeploy(world):
    _, vercel, cycle = world
    unmanaged_preview_a(vercel)
    state = {}
    assert cycle(state, apply=True) == 1
    cycle(state, now=60, apply=True)
    assert len(vercel.redeploys) == 1
    calls = len(vercel.calls)
    assert cycle(state, now=120, apply=True) == 0
    assert len(vercel.calls) == calls


def test_registry_edit_applies_on_the_next_cycle(world):
    bao, vercel, cycle = world
    unmanaged_preview_a(vercel)
    state = {}
    cycle(state, apply=True)
    cycle(state, now=60, apply=True)
    adopted = json.loads(json.dumps(RECORD))
    adopted["syncs"][1]["adopt"] = True
    put(bao, "registry/data/webapp", adopted)
    assert cycle(state, now=120, apply=True) == 0
    assert vercel.values["env_manual"] == "dev-a1"


def test_non_string_values_write_nothing(world):
    bao, vercel, cycle = world
    put(bao, f"{MOUNT}/data/prod/app/public", {"NEXT_PUBLIC_A": 1, "NEXT_PUBLIC_B": "prod-b1"})
    assert cycle({}, apply=True) == 1
    assert {target for _, target in by_key_target(vercel)} == {"preview"}


@pytest.fixture
def daemon(bao, tmp_path, monkeypatch):
    def start(period):
        token = json.loads(
            cli("token", "create", "-orphan", f"-period={period}", "-format=json")
            if period
            else cli("token", "create", "-orphan", "-format=json")
        )
        (tmp_path / "token").write_text(token["auth"]["client_token"])
        monkeypatch.setenv("BAO_SYNC_TOKEN_FILE", str(tmp_path / "token"))
        monkeypatch.setenv("BAO_ADDR", bao)
        monkeypatch.setenv("STATE_DIRECTORY", str(tmp_path))
        return tmp_path / "state.json"

    return start


def test_apply_looks_up_the_token_only_near_renewal(daemon, monkeypatch):
    daemon("1h")
    lookups = []
    monkeypatch.setattr(
        Bao, "lookup", lambda self, original=Bao.lookup: lookups.append(1) or original(self)
    )
    assert main(["apply"]) == 0
    assert main(["apply"]) == 0
    assert len(lookups) == 1


def test_non_periodic_token_is_refused(daemon):
    daemon(None)
    with pytest.raises(SystemExit, match="periodic"):
        main(["apply"])


def test_corrupt_state_starts_fresh(daemon):
    state = daemon("1h")
    state.write_text("{")
    assert main(["apply"]) == 0
    assert json.loads(state.read_text())["token_check_at"] > 0
