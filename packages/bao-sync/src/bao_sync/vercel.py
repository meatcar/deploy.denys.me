"""Vercel project env destination."""

import re
from dataclasses import dataclass

from .http import request

MARKER = re.compile(r"bao-sync (\S+) v(\d+)")


@dataclass(frozen=True)
class Change:
    kind: str  # create, update, keep, skip
    key: str
    env_id: str | None = None
    reason: str = ""


def marker(source, version):
    return f"bao-sync {source} v{version}"


def plan(sync, source, version, remotes, known):
    """Decide per key; never touch unmarked, shared or newer remote records."""
    return [_plan_key(sync, source, version, key, remotes, known.get(key)) for key in sync.keys]


def _plan_key(sync, source, version, key, remotes, known):
    scoped = [
        record
        for record in remotes
        if record["key"] == key
        and sync.target in record["target"]
        and not record.get("gitBranch")
        and not record.get("customEnvironmentIds")
    ]
    if not scoped:
        return Change("create", key)
    record = scoped[0]
    env_id = record["id"]
    if record["target"] != [sync.target]:
        return Change("skip", key, env_id, "shared with other targets")
    owner = MARKER.fullmatch(record.get("comment") or "")
    if not owner and not sync.adopt:
        return Change("skip", key, env_id, "not managed")
    if owner and owner[1] == source and int(owner[2]) > version:
        return Change("skip", key, env_id, f"remote v{owner[2]} is newer than bao v{version}")
    verified = known == {"id": env_id, "updated_at": record["updatedAt"], "version": version}
    if verified and record["type"] == "sensitive":
        return Change("keep", key, env_id)
    return Change("update", key, env_id)


class Vercel:
    def __init__(self, destination, token, api="https://api.vercel.com"):
        self.api = api.rstrip("/")
        self.project = destination.project_id
        self.query = f"?teamId={destination.team_id}"
        self.headers = {"Authorization": f"Bearer {token}"}

    def _call(self, method, path, body=None, query=""):
        return request(method, self.api + path + self.query + query, self.headers, body)

    def env(self):
        return self._call("GET", f"/v10/projects/{self.project}/env")["envs"]

    def create(self, key, value, target, comment):
        body = {
            "key": key,
            "value": value,
            "type": "sensitive",
            "target": [target],
            "comment": comment,
        }
        created = self._call("POST", f"/v10/projects/{self.project}/env", body)["created"]
        return created[0] if isinstance(created, list) else created

    def update(self, env_id, value, comment):
        body = {"value": value, "type": "sensitive", "comment": comment}
        return self._call("PATCH", f"/v9/projects/{self.project}/env/{env_id}", body)

    def redeploy_production(self):
        """Rebuild the current production deployment with current env, keeping build cache."""
        latest = self._call(
            "GET",
            "/v6/deployments",
            query=f"&projectId={self.project}&target=production&state=READY&limit=1",
        )["deployments"]
        if not latest:
            return None
        body = {
            "deploymentId": latest[0]["uid"],
            "name": latest[0]["name"],
            "target": "production",
            "meta": {"action": "redeploy"},
        }
        return self._call("POST", "/v13/deployments", body)["id"]
