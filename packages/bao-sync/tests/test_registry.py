import copy

import pytest

from bao_sync.registry import Sync, parse_project

RECORD = {
    "project": "acme/webapp",
    "amp": {
        "project_id": "7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f",
        "subject": "user:user_x:project:7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f",
    },
    "environments": {
        "dev": {"app": ["public", "varlock"]},
        "prod": {"app": ["public", "varlock"], "admin": ["ci-e2e", "sync-vercel"]},
    },
    "amp_grants": ["dev/app/public"],
    "agent_writes": ["dev/app/varlock", "prod/app/varlock"],
    "destinations": {
        "vercel": {
            "type": "vercel",
            "project_id": "prj_abc",
            "team_id": "team_abc",
            "credential": "prod/admin/sync-vercel",
        },
    },
    "syncs": [
        {
            "source": "prod/app/public",
            "destination": "vercel",
            "target": "production",
            "keys": ["NEXT_PUBLIC_POSTHOG_KEY"],
            "redeploy": True,
        },
        {
            "source": "dev/app/public",
            "destination": "vercel",
            "target": "preview",
            "keys": ["NEXT_PUBLIC_POSTHOG_KEY"],
        },
        {
            "source": "dev/app/varlock",
            "destination": "vercel",
            "target": "preview",
            "keys": ["_VARLOCK_ENV_KEY"],
            "adopt": True,
        },
    ],
}


def record(**changes):
    value = copy.deepcopy(RECORD)
    for path, new in changes.items():
        *parents, leaf = path.split("__")
        node = value
        for part in parents:
            node = node[int(part)] if part.isdigit() else node[part]
        node[leaf] = new
    return value


def test_valid_record_resolves_mount_credentials_and_syncs():
    project = parse_project(RECORD)
    assert project.name == "acme/webapp"
    assert project.mount == "projects/acme/webapp"
    assert project.destinations["vercel"].credential == "prod/admin/sync-vercel"
    assert project.syncs[0] == Sync(
        source="prod/app/public",
        destination="vercel",
        target="production",
        keys=("NEXT_PUBLIC_POSTHOG_KEY",),
        redeploy=True,
        adopt=False,
    )
    assert project.syncs[2].adopt and not project.syncs[2].redeploy


@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"syncs__0__target": "preview"}, "prod sources sync only to production"),
        ({"syncs__1__target": "production"}, "only prod sources sync to production"),
        ({"syncs__1__source": "dev/app/payload"}, "not declared"),
        ({"syncs__1__source": "dev/app"}, "not declared"),
        ({"syncs__0__source": "prod/admin/sync-vercel"}, "destination credential"),
        ({"syncs__0__destination": "github"}, "unknown destination"),
        ({"syncs__0__target": "staging"}, "target"),
        ({"syncs__0__keys": []}, "keys"),
        ({"syncs__0__keys": ["BAD-NAME"]}, "keys"),
        ({"syncs__0__keys": ["A", "A"]}, "keys"),
        ({"syncs__0__redploy": True}, "unknown field"),
        ({"syncs__0__redeploy": "yes"}, "boolean"),
        ({"syncs__1__redeploy": True}, "production only"),
        ({"destinations__vercel__extra": "x"}, "unknown field"),
        ({"destinations__vercel__credential": "prod/app/public"}, "credential"),
        ({"destinations__vercel__credential": "prod/admin/missing"}, "credential"),
        ({"destinations__vercel__type": "netlify"}, "type"),
        ({"project": "Acme/webapp"}, "project"),
        ({"project": "acme/web/app"}, "project"),
        ({"project": "../webapp"}, "project"),
        ({"project": "acme/webapp\n"}, "project"),
        ({"syncs__0__keys": ["A\n"]}, "keys"),
        ({"destinations__vercel__team_id": "team_abc\n"}, "team_id"),
        ({"destinations__vercel__project_id": "prj_abc/../other"}, "project_id"),
        ({"destinations__vercel__team_id": "team_abc&slug=x"}, "team_id"),
        ({"agent_writes": "dev/app/varlock"}, "agent_writes"),
        ({"agent_writes": ["dev/app/payload"]}, "agent_writes"),
        ({"agent_writes": ["prod/admin/sync-vercel"]}, "agent_writes"),
        ({"agent_writes": ["dev/app"]}, "agent_writes"),
        ({"agent_writes": [["dev/app/varlock"]]}, "agent_writes"),
    ],
)
def test_invalid_records_fail_closed(changes, message):
    with pytest.raises(ValueError, match=message):
        parse_project(record(**changes))


def test_duplicate_destination_key_is_rejected_per_target_only():
    duplicate = record()
    duplicate["syncs"].append(
        {
            "source": "dev/app/varlock",
            "destination": "vercel",
            "target": "preview",
            "keys": ["NEXT_PUBLIC_POSTHOG_KEY"],
        }
    )
    with pytest.raises(ValueError, match="NEXT_PUBLIC_POSTHOG_KEY.*preview"):
        parse_project(duplicate)
    other_target = record()
    other_target["syncs"].append(
        {
            "source": "dev/app/varlock",
            "destination": "vercel",
            "target": "development",
            "keys": ["NEXT_PUBLIC_POSTHOG_KEY"],
        }
    )
    assert len(parse_project(other_target).syncs) == 4
