"""Read-only OpenBao client for the sync token."""

from urllib.parse import quote

from .http import HTTPError, request

REGISTRY = "registry"


class Bao:
    def __init__(self, address, token):
        self.address = address.rstrip("/")
        self.headers = {"X-Vault-Token": token}

    def _call(self, method, path, body=None, query=""):
        return request(method, f"{self.address}/v1/{quote(path)}{query}", self.headers, body)

    def committed_index(self):
        """Raft write counter; unauthenticated, unaudited, unchanged by reads. None off Raft."""
        return request("GET", f"{self.address}/v1/sys/leader", {}).get("raft_committed_index")

    def registry(self):
        try:
            keys = self._call("LIST", f"{REGISTRY}/metadata/")["data"]["keys"]
        except HTTPError as error:
            if error.status == 404:
                return {}
            raise
        return {key: self._record(key) for key in keys if not key.endswith("/")}

    def _record(self, key):
        """None for a deleted record, so the caller rejects it alone."""
        try:
            return self._call("GET", f"{REGISTRY}/data/{key}")["data"]["data"]
        except HTTPError as error:
            if error.status == 404:
                return None
            raise

    def versions(self, mount, folder):
        """Current live version per document in one folder; None when deleted or destroyed."""
        try:
            info = self._call("LIST", f"{mount}/detailed-metadata/{folder}/")["data"]["key_info"]
        except HTTPError as error:
            if error.status == 404:
                return {}
            raise
        versions = {}
        for name, meta in info.items():
            current = meta.get("current_version") or 0
            entry = (meta.get("versions") or {}).get(str(current), {})
            live = current and not entry.get("deletion_time") and not entry.get("destroyed")
            versions[name] = current if live else None
        return versions

    def read(self, mount, path, version):
        return self._call("GET", f"{mount}/data/{path}", query=f"?version={version}")["data"][
            "data"
        ]

    def lookup(self):
        return self._call("GET", "auth/token/lookup-self")["data"]

    def renew(self):
        self._call("POST", "auth/token/renew-self", {})
