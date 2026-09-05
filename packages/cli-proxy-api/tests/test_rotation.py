import socket
import subprocess
import time
import urllib.request
from functools import partial

import pytest

from cli_proxy_api.rotate_admin import Bao
from cli_proxy_api.rotate_admin import rotate as rotate_admin

SECRET_PATH = "gitlab/customer/project/staging/admin"
rotate = partial(rotate_admin, secret_path=SECRET_PATH, base_url="https://manager.example.test")


@pytest.fixture
def bao(tmp_path, monkeypatch):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        address = "127.0.0.1:" + str(listener.getsockname()[1])
    url = "http://" + address
    for name, value in {
        "HOME": str(tmp_path),
        "BAO_ADDR": url,
        "VAULT_ADDR": url,
        "BAO_TOKEN": "test-only",
        "VAULT_TOKEN": "test-only",
        "BAO_NAMESPACE": "",
        "VAULT_NAMESPACE": "",
        "NO_PROXY": "127.0.0.1",
        "no_proxy": "127.0.0.1",
    }.items():
        monkeypatch.setenv(name, value)
    with (tmp_path / "bao.log").open("w") as log:
        server = subprocess.Popen(
            [
                "bao",
                "server",
                "-dev",
                "-dev-no-store-token",
                "-dev-root-token-id=test-only",
                "-dev-listen-address=" + address,
            ],
            stdout=log,
            stderr=log,
        )
        try:
            for _ in range(100):
                try:
                    with urllib.request.urlopen(url + "/v1/sys/health", timeout=1):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                pytest.fail("Disposable Bao did not start")
            subprocess.run(
                ["bao", "secrets", "enable", "-path=applications", "kv-v2"],
                check=True,
                capture_output=True,
            )
            yield Bao("applications")
        finally:
            server.terminate()
            server.wait(timeout=10)


@pytest.mark.parametrize("lost_path", [SECRET_PATH + "-pending", SECRET_PATH])
def test_lost_write_acknowledgement_reuses_generation(bao, lost_path):
    class LostResponse(Bao):
        def write(self, path, value, version):
            super().write(path, value, version)
            if path == lost_path:
                raise TimeoutError("Response lost after durable write")

    calls = []

    def host(action, value=None):
        calls.append((action, value))

    with pytest.raises(TimeoutError):
        rotate(1, LostResponse("applications"), host)
    pending = bao.read(SECRET_PATH + "-pending")
    rotate(1, bao, host)
    rotate(1, bao, host)
    assert bao.read(SECRET_PATH + "-pending") == pending
    assert bao.read(SECRET_PATH) == (pending[0]["secret"], 1)
    assert calls[-1] == ("commit", {"generation": 1})


def test_failed_verification_cannot_publish_or_skip_generation(bao):
    def host(action, value=None):
        if action == "verify":
            raise RuntimeError("Target unavailable")

    with pytest.raises(RuntimeError):
        rotate(1, bao, host)
    pending = bao.read(SECRET_PATH + "-pending")
    assert bao.read(SECRET_PATH) == (None, 0)
    with pytest.raises(ValueError):
        rotate(2, bao, host)
    assert bao.read(SECRET_PATH + "-pending") == pending
    with pytest.raises(subprocess.CalledProcessError):
        bao.write(SECRET_PATH + "-pending", {"wrong": True}, 0)
    assert bao.read(SECRET_PATH + "-pending") == pending


def test_lost_host_acknowledgement_finishes_before_next_generation(bao):
    acknowledged = 0
    fail = True

    def host(action, value=None):
        nonlocal acknowledged, fail
        if action == "stage" and value["generation"] > acknowledged + 1:
            raise ValueError("Previous generation not acknowledged")
        if action == "commit":
            if fail:
                fail = False
                raise TimeoutError("Disconnected before acknowledgement")
            acknowledged = value["generation"]

    with pytest.raises(TimeoutError):
        rotate(1, bao, host)
    rotate(2, bao, host)
    assert acknowledged == 2
    assert bao.read(SECRET_PATH)[0]["generation"] == 2


def test_projects_rotate_independently_and_publish_their_endpoint(bao):
    for project in ("alpha", "beta"):
        rotate_admin(
            1,
            bao,
            lambda *args: None,
            secret_path=project + "/admin",
            base_url=f"https://{project}.example.test",
        )
    alpha = bao.read("alpha/admin")[0]
    beta = bao.read("beta/admin")[0]
    assert alpha["base_url"] == "https://alpha.example.test"
    assert beta["base_url"] == "https://beta.example.test"
    assert alpha["admin_key"] != beta["admin_key"]
    with pytest.raises(ValueError, match="endpoint"):
        rotate_admin(
            1,
            bao,
            lambda *args: pytest.fail("Must not contact a different host on retry"),
            secret_path="alpha/admin",
            base_url="https://beta.example.test",
        )
