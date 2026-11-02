import itertools
import json
import re
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


@pytest.fixture(scope="session")
def bao(tmp_path_factory):
    """Raft-backed OpenBao, so sys/leader reports raft_committed_index like the live host."""
    tmp_path = tmp_path_factory.mktemp("bao")
    monkeypatch = pytest.MonkeyPatch()
    port = free_port()
    url = f"http://127.0.0.1:{port}"
    (tmp_path / "raft").mkdir()
    (tmp_path / "bao.hcl").write_text(f"""
storage "raft" {{
  path    = "{tmp_path}/raft"
  node_id = "test"
}}
listener "tcp" {{
  address     = "127.0.0.1:{port}"
  tls_disable = true
}}
api_addr      = "{url}"
cluster_addr  = "http://127.0.0.1:{free_port()}"
disable_mlock = true
""")
    for name, value in {
        "HOME": str(tmp_path),
        "BAO_ADDR": url,
        "BAO_NAMESPACE": "",
        "NO_PROXY": "127.0.0.1",
        "no_proxy": "127.0.0.1",
    }.items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("BAO_TOKEN", raising=False)
    with (tmp_path / "bao.log").open("w") as log:
        server = subprocess.Popen(
            ["bao", "server", "-config", str(tmp_path / "bao.hcl")], stdout=log, stderr=log
        )
        try:
            wait(lambda: urllib.request.urlopen(url + "/v1/sys/seal-status", timeout=1))
            init = json.loads(
                subprocess.run(
                    [
                        "bao",
                        "operator",
                        "init",
                        "-key-shares=1",
                        "-key-threshold=1",
                        "-format=json",
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout
            )
            subprocess.run(
                ["bao", "operator", "unseal", init["unseal_keys_b64"][0]],
                check=True,
                capture_output=True,
            )
            monkeypatch.setenv("BAO_TOKEN", init["root_token"])
            wait(
                lambda: (
                    json.load(urllib.request.urlopen(url + "/v1/sys/leader"))["is_self"]
                    or (_ for _ in ()).throw(OSError())
                )
            )
            wait(lambda: cli("secrets", "list"))
            yield url
        finally:
            server.terminate()
            server.wait(timeout=10)
            monkeypatch.undo()


def wait(probe):
    for _ in range(200):
        try:
            probe()
            return
        except (OSError, subprocess.CalledProcessError):
            time.sleep(0.05)
    pytest.fail("Disposable Bao did not become ready")


def cli(*args, stdin=None):
    return subprocess.run(
        ["bao", *args], check=True, capture_output=True, text=True, input=stdin
    ).stdout


class Reject(Exception):
    def __init__(self, status, retry_after=None):
        self.status, self.retry_after = status, retry_after


class FakeVercel:
    """Mirrors behaviour verified live: PATCH bumps updatedAt; lists hide sensitive values."""

    def __init__(self):
        self.reject_next_write = None
        self.envs = {}
        self.values = {}
        self.calls = []
        self.redeploys = []
        self.clock = itertools.count(1000)
        self.ids = itertools.count(1)

    def handle(self, method, path, query, body, headers):
        assert headers.get("Authorization") == "Bearer vercel-test-token"
        assert query.get("teamId") == "team_abc"
        self.calls.append((method, path))
        if method != "GET" and self.reject_next_write:
            reject, self.reject_next_write = self.reject_next_write, None
            raise reject
        if (method, path) == ("GET", "/v10/projects/prj_abc/env"):
            return {"envs": [dict(env, value="") for env in self.envs.values()]}
        if (method, path) == ("POST", "/v10/projects/prj_abc/env"):
            env_id = f"env_{next(self.ids)}"
            self.envs[env_id] = {
                "id": env_id,
                "key": body["key"],
                "type": body["type"],
                "target": body["target"],
                "comment": body["comment"],
                "updatedAt": next(self.clock),
            }
            self.values[env_id] = body["value"]
            return {"created": dict(self.envs[env_id])}
        if method == "PATCH" and (match := re.fullmatch(r"/v9/projects/prj_abc/env/(.+)", path)):
            env = self.envs[match[1]]
            env.update(
                type=body.get("type", env["type"]),
                comment=body.get("comment", env["comment"]),
                updatedAt=next(self.clock),
            )
            if "value" in body:
                self.values[env["id"]] = body["value"]
            return dict(env)
        if (method, path) == ("GET", "/v6/deployments"):
            assert query["target"] == "production" and query["projectId"] == "prj_abc"
            return {"deployments": [{"uid": "dpl_current", "name": "webapp"}]}
        if (method, path) == ("POST", "/v13/deployments"):
            self.redeploys.append(body)
            return {"id": f"dpl_{len(self.redeploys)}"}
        raise AssertionError(f"unexpected {method} {path}")

    def writes(self):
        return [call for call in self.calls if call[0] in ("POST", "PATCH")]


@pytest.fixture
def vercel():
    fake = FakeVercel()

    class Handler(BaseHTTPRequestHandler):
        def _serve(self):
            path, _, raw = self.path.partition("?")
            query = dict(part.split("=", 1) for part in raw.split("&") if part)
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length)) if length else None
            try:
                payload = json.dumps(fake.handle(self.command, path, query, body, self.headers))
            except Reject as reject:
                self.send_response(reject.status)
                if reject.retry_after:
                    self.send_header("Retry-After", reject.retry_after)
                self.end_headers()
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(payload.encode())

        do_GET = do_POST = do_PATCH = _serve

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    fake.url = f"http://127.0.0.1:{server.server_port}"
    yield fake
    server.shutdown()
