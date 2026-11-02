"""One sync cycle: Bao registry and documents to destinations. Logs names, never values."""

import copy
import dataclasses
import json
import logging

from .http import HTTPError
from .registry import parse_project
from .vercel import Vercel, marker, plan

FULL_INTERVAL = 3600
log = logging.getLogger("bao-sync")


def run(bao, state, now, *, apply, force=False, clients=None):
    """Return the error count. Dry runs work on a copy and leave state untouched."""
    clients = clients or {"vercel": Vercel}
    working = state if apply else copy.deepcopy(state)
    memories = working.setdefault("projects", {})
    index = bao.committed_index()
    pending = any(
        memory.get("redeploy") or memory.get("retry")
        for project in memories.values()
        for memory in project.values()
    )
    full = force or not apply or now - working.get("full_at", 0) >= FULL_INTERVAL
    if not full and not pending and index is not None and index == working.get("index"):
        return 0
    errors = 0
    projects = {}
    for key, record in sorted(bao.registry().items()):
        try:
            project = parse_project(record)
        except (ValueError, AttributeError, TypeError) as error:
            log.error("registry %s rejected: %s", key, error)
            errors += 1
            continue
        projects.setdefault(project.name, []).append(project)
    for name, candidates in sorted(projects.items()):
        if len(candidates) > 1:
            log.error("registry %s: project declared %d times", name, len(candidates))
            errors += 1
            continue
        project = candidates[0]
        for label, destination in sorted(project.destinations.items()):
            memory = memories.setdefault(name, {}).setdefault(label, {})
            if now < memory.get("retry_at", 0):
                continue
            try:
                errors += _destination(
                    bao, project, label, destination, memory, clients, apply=apply, full=full
                )
                memory.pop("retry", None)
                memory.pop("retry_at", None)
            except Exception as error:  # noqa: BLE001 - isolate destinations; retried next cycle
                log.error("%s %s failed: %s", name, label, error)
                errors += 1
                memory["retry"] = True
                if isinstance(error, HTTPError) and str(error.retry_after or "").isdigit():
                    memory["retry_at"] = now + int(error.retry_after)
    working["index"] = index
    if full:
        working["full_at"] = now
    return errors


def _destination(bao, project, label, destination, memory, clients, *, apply, full):
    syncs = [sync for sync in project.syncs if sync.destination == label]
    folders = {sync.source.rsplit("/", 1)[0] for sync in syncs}
    current = {}
    for folder in folders:
        for name, version in bao.versions(project.mount, folder).items():
            current[f"{folder}/{name}"] = version
    seen = memory.setdefault("versions", {})
    config = json.dumps(
        [dataclasses.asdict(destination), [dataclasses.asdict(sync) for sync in syncs]],
        sort_keys=True,
    )
    if (
        not full
        and not memory.get("redeploy")
        and memory.get("config") == config
        and all(current.get(sync.source) == seen.get(sync.source) for sync in syncs)
    ):
        return 0
    token = bao.read(project.mount, destination.credential, 0)["token"]
    client = clients[destination.type](destination, token)
    remotes = client.env()
    errors = 0
    wrote = False
    for sync in syncs:
        version = current.get(sync.source)
        if version is None:
            log.warning("%s %s: source deleted; destination retained", project.name, sync.source)
            errors += 1
            continue
        source = f"{project.mount}/{sync.source}"
        known = memory.setdefault("known", {}).setdefault(sync.target, {})
        changes = plan(sync, source, version, remotes, known)
        for change in changes:
            if change.kind == "skip":
                log.warning(
                    "%s %s %s %s: %s", project.name, label, sync.target, change.key, change.reason
                )
                errors += 1
        writes = [change for change in changes if change.kind in ("create", "update")]
        if not writes:
            seen[sync.source] = version
            continue
        values = bao.read(project.mount, sync.source, version)
        if set(values) != set(sync.keys) or not all(isinstance(v, str) for v in values.values()):
            log.error(
                "%s %s: fields must be exactly the declared keys, as strings; nothing written",
                project.name,
                sync.source,
            )
            errors += 1
            continue
        for change in writes:
            log.info(
                "%s %s %s %s %s v%s",
                "apply" if apply else "plan",
                change.kind,
                project.name,
                sync.target,
                change.key,
                version,
            )
            if not apply:
                continue
            comment = marker(source, version)
            if change.kind == "create":
                result = client.create(change.key, values[change.key], sync.target, comment)
            else:
                result = client.update(change.env_id, values[change.key], comment)
            known[change.key] = {
                "id": result["id"],
                "updated_at": result["updatedAt"],
                "version": version,
            }
            wrote = True
            memory["redeploy"] = memory.get("redeploy") or sync.redeploy
        seen[sync.source] = version
    # NOTE: Redeploy one quiet cycle after the last write, so a burst of edits builds once.
    if apply and memory.get("redeploy") and not wrote:
        log.info("apply redeploy %s %s", project.name, label)
        client.redeploy_production()
        memory["redeploy"] = False
    memory["config"] = config
    return errors
