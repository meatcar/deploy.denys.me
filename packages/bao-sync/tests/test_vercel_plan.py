import pytest

from bao_sync.registry import Sync
from bao_sync.vercel import Change, marker, plan

SOURCE = "projects/acme/webapp/dev/app/public"
SYNC = Sync(source="dev/app/public", destination="vercel", target="preview", keys=("KEY",))


def remote(env_id="env_1", version=3, updated=100, target=("preview",), **extra):
    record = {
        "id": env_id,
        "key": "KEY",
        "type": "sensitive",
        "target": list(target),
        "updatedAt": updated,
        "comment": marker(SOURCE, version) if version else "",
    }
    return record | extra


def state(env_id="env_1", updated=100, version=3):
    return {"KEY": {"id": env_id, "updated_at": updated, "version": version}}


def changes(remotes, known=None, version=3, sync=SYNC):
    return plan(sync, SOURCE, version, remotes, known or {})


def test_missing_remote_is_created():
    assert changes([]) == [Change("create", "KEY")]


def test_unchanged_remote_with_matching_state_is_kept():
    assert changes([remote()], state()) == [Change("keep", "KEY", "env_1")]


def test_new_bao_version_updates():
    assert changes([remote()], state(), version=4) == [Change("update", "KEY", "env_1")]


@pytest.mark.parametrize("known", [{}, state(updated=99), state(env_id="env_0")])
def test_unverified_or_drifted_remote_is_rewritten(known):
    assert changes([remote()], known) == [Change("update", "KEY", "env_1")]


def test_remote_newer_than_bao_is_never_overwritten():
    assert changes([remote(version=5)], {}, version=4) == [
        Change("skip", "KEY", "env_1", "remote v5 is newer than bao v4")
    ]


def test_marker_from_another_source_moves_without_version_check():
    moved = remote(version=9, comment=marker("projects/acme/webapp/dev/app/old", 9))
    assert changes([moved], {}, version=1) == [Change("update", "KEY", "env_1")]


def test_unmarked_remote_needs_adopt():
    assert changes([remote(version=None)]) == [Change("skip", "KEY", "env_1", "not managed")]
    adopting = Sync(**(SYNC.__dict__ | {"adopt": True}))
    assert changes([remote(version=None)], sync=adopting) == [Change("update", "KEY", "env_1")]


def test_remote_shared_across_targets_is_never_touched():
    shared = remote(target=("preview", "production"))
    adopting = Sync(**(SYNC.__dict__ | {"adopt": True}))
    assert changes([shared], sync=adopting) == [
        Change("skip", "KEY", "env_1", "shared with other targets")
    ]


def test_out_of_scope_records_are_ignored():
    others = [
        remote("env_2", target=("development",)),
        remote("env_3", gitBranch="feature"),
        remote("env_4", customEnvironmentIds=["env_custom"]),
        remote("env_5", key="OTHER"),
    ]
    assert changes(others) == [Change("create", "KEY")]


def test_non_sensitive_owned_remote_is_rewritten_as_sensitive():
    assert changes([remote(type="encrypted")], state()) == [Change("update", "KEY", "env_1")]


def test_marker_round_trip_rejects_lookalikes():
    assert marker(SOURCE, 7) == "bao-sync projects/acme/webapp/dev/app/public v7"
    lookalike = remote(comment="bao-sync projects/acme/webapp/dev/app/public v7 edited")
    assert changes([lookalike]) == [Change("skip", "KEY", "env_1", "not managed")]
