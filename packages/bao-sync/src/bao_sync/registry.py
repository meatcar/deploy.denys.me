"""Project registry records: one Bao KV record per project, validated fail-closed."""

import re
from dataclasses import dataclass

SEGMENT = re.compile(r"[a-z0-9][a-z0-9._-]*")
KEY = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ID = re.compile(r"[A-Za-z0-9_]+")
TARGETS = {"vercel": {"production", "preview", "development"}}
DESTINATION_FIELDS = {"vercel": {"type", "project_id", "team_id", "credential"}}
SYNC_FIELDS = {"source", "destination", "target", "keys", "redeploy", "adopt"}


@dataclass(frozen=True)
class Destination:
    type: str
    credential: str
    project_id: str
    team_id: str


@dataclass(frozen=True)
class Sync:
    source: str
    destination: str
    target: str
    keys: tuple[str, ...]
    redeploy: bool = False
    adopt: bool = False


@dataclass(frozen=True)
class Project:
    name: str
    destinations: dict[str, Destination]
    syncs: tuple[Sync, ...]

    @property
    def mount(self):
        return "projects/" + self.name


def parse_project(record):
    if not isinstance(record, dict):
        raise ValueError("record is deleted or not an object")
    name = record.get("project")
    if (
        not isinstance(name, str)
        or len(name.split("/")) != 2
        or not all(SEGMENT.fullmatch(part) and part not in (".", "..") for part in name.split("/"))
    ):
        raise ValueError(f"invalid project name {name!r}")
    declared = {
        f"{environment}/{cls}/{document}"
        for environment, classes in record.get("environments", {}).items()
        for cls, documents in classes.items()
        for document in documents
    }
    agent_writes = record.get("agent_writes", [])
    if not isinstance(agent_writes, list) or not all(
        isinstance(document, str)
        and document in declared
        and document.split("/")[1] in ("app", "inference")
        for document in agent_writes
    ):
        raise ValueError("agent_writes must list declared app or inference documents")
    destinations = {
        label: _destination(label, spec, declared)
        for label, spec in record.get("destinations", {}).items()
    }
    credentials = {destination.credential for destination in destinations.values()}
    syncs = tuple(
        _sync(spec, declared, destinations, credentials) for spec in record.get("syncs", [])
    )
    seen = set()
    for sync in syncs:
        for key in sync.keys:
            scope = (sync.destination, sync.target, key)
            if scope in seen:
                raise ValueError(f"{key} is synced twice to {sync.destination} {sync.target}")
            seen.add(scope)
    return Project(name=name, destinations=destinations, syncs=syncs)


def _destination(label, spec, declared):
    kind = spec.get("type")
    if kind not in DESTINATION_FIELDS:
        raise ValueError(f"destination {label}: unsupported type {kind!r}")
    _exact_fields(f"destination {label}", spec, DESTINATION_FIELDS[kind], DESTINATION_FIELDS[kind])
    for field in ("project_id", "team_id"):
        if not isinstance(spec[field], str) or not ID.fullmatch(spec[field]):
            raise ValueError(f"destination {label}: invalid {field}")
    credential = spec["credential"]
    if credential not in declared or not credential.startswith("prod/admin/"):
        raise ValueError(f"destination {label}: credential must be a declared prod/admin document")
    return Destination(
        type=kind, credential=credential, project_id=spec["project_id"], team_id=spec["team_id"]
    )


def _sync(spec, declared, destinations, credentials):
    _exact_fields("sync", spec, SYNC_FIELDS, {"source", "destination", "target", "keys"})
    source, label, target, keys = spec["source"], spec["destination"], spec["target"], spec["keys"]
    if source not in declared:
        raise ValueError(f"sync source {source!r} is not declared")
    if source in credentials:
        raise ValueError(f"sync source {source!r} is a destination credential")
    if label not in destinations:
        raise ValueError(f"sync to unknown destination {label!r}")
    if target not in TARGETS[destinations[label].type]:
        raise ValueError(f"sync {source}: unsupported target {target!r}")
    if source.startswith("prod/") and target != "production":
        raise ValueError(f"sync {source}: prod sources sync only to production")
    if target == "production" and not source.startswith("prod/"):
        raise ValueError(f"sync {source}: only prod sources sync to production")
    if spec.get("redeploy") and target != "production":
        raise ValueError(f"sync {source}: redeploy applies to production only")
    if (
        not isinstance(keys, list)
        or not keys
        or len(set(keys)) != len(keys)
        or not all(isinstance(key, str) and KEY.fullmatch(key) for key in keys)
    ):
        raise ValueError(f"sync {source}: keys must be unique env var names")
    if not all(isinstance(spec.get(flag, False), bool) for flag in ("redeploy", "adopt")):
        raise ValueError(f"sync {source}: redeploy and adopt must be boolean")
    return Sync(
        source=source,
        destination=label,
        target=target,
        keys=tuple(keys),
        redeploy=spec.get("redeploy", False),
        adopt=spec.get("adopt", False),
    )


def _exact_fields(context, spec, allowed, required):
    if unknown := set(spec) - allowed:
        raise ValueError(f"{context}: unknown field {sorted(unknown)}")
    if missing := required - set(spec):
        raise ValueError(f"{context}: missing field {sorted(missing)}")
