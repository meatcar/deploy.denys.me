import json
import os
import shlex
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path

import pytest

from cli_proxy_api import admin
from cli_proxy_api.deploy_key import deploy_key
from cli_proxy_api.initialize import initialize

pytestmark = pytest.mark.containers


def podman(*args):
    return subprocess.check_output(["podman", *args], text=True, stderr=subprocess.PIPE).strip()


def get(url, key=None):
    headers = {"Authorization": "Bearer " + key} if key else {}
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, headers=headers), timeout=10
        ) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


@dataclass
class Stack:
    state: Path
    api: str
    manager: str
    api_key: str
    admin_key: str
    service: str
    image: str


@pytest.fixture(scope="session")
def api_image():
    archive = os.environ.get("CPA_TEST_IMAGE")
    if not archive:
        pytest.fail("Container tests require CPA_TEST_IMAGE")
    podman("load", "-i", archive)
    return "localhost/cli-proxy-api:7.3.4-pi-0.9.1"


@pytest.fixture
def stack(tmp_path, api_image):
    prefix = "cli-proxy-api-test-" + uuid.uuid4().hex[:12]
    (tmp_path / "auth").mkdir()
    initialize(
        tmp_path / "config.yaml",
        json.loads(os.environ["CLI_PROXY_API_TEST_SETTINGS"]),
    )
    config = json.loads((tmp_path / "config.yaml").read_text())
    try:
        podman("network", "create", prefix)
        podman(
            "run",
            "-d",
            "--name",
            prefix + "-api",
            "--network",
            prefix,
            "--network-alias",
            "cli-proxy-api",
            "--read-only",
            "--cap-drop=all",
            "--security-opt=no-new-privileges",
            "--tmpfs",
            "/tmp",
            "-v",
            str(tmp_path) + ":/CLIProxyAPI/state",
            "-p",
            "127.0.0.1::8317",
            api_image,
            "-config",
            "/CLIProxyAPI/state/config.yaml",
        )
        podman(
            "run",
            "-d",
            "--name",
            prefix + "-manager",
            "--network",
            prefix,
            "--network-alias",
            "cpa-manager-plus",
            "--read-only",
            "--cap-drop=all",
            "--security-opt=no-new-privileges",
            "--tmpfs",
            "/tmp",
            "-v",
            str(tmp_path / "manager") + ":/data",
            "-v",
            str(tmp_path / "management-key") + ":/run/secrets/cpa-management-key:ro",
            "-e",
            "CPA_MANAGER_ADMIN_KEY_FILE=/data/admin-key",
            "-e",
            "CPA_MANAGEMENT_KEY_FILE=/run/secrets/cpa-management-key",
            "-e",
            "CPA_UPSTREAM_URL=http://cli-proxy-api:8317",
            "-p",
            "127.0.0.1::18317",
            "docker.io/seakee/cpa-manager-plus:v1.12.13@sha256:8a51d4b62bc2044772bf2f4aa516ac1c5cc06ad09ac24690bc773c68464b8675",
        )
        api = "http://" + podman("port", prefix + "-api", "8317/tcp")
        manager = "http://" + podman("port", prefix + "-manager", "18317/tcp")
        for _ in range(30):
            try:
                if get(api + "/v1/models")[0] == 401 and get(manager + "/health")[0] == 200:
                    break
            except (urllib.error.URLError, ConnectionError):
                pass
            time.sleep(0.1)
        else:
            pytest.fail("CLIProxyAPI stack did not start")
        yield Stack(
            tmp_path,
            api,
            manager,
            config["api-keys"][0],
            (tmp_path / "manager/admin-key").read_text().strip(),
            prefix + "-manager",
            podman("inspect", "--format", "{{.Image}}", prefix + "-manager"),
        )
    finally:
        for name in [prefix + "-manager", prefix + "-api"]:
            subprocess.run(["podman", "rm", "-f", name], capture_output=True)
        subprocess.run(["podman", "network", "rm", prefix], capture_output=True)


@pytest.fixture
def admin_command(stack, tmp_path, monkeypatch):
    binaries = tmp_path / "test-bin"
    binaries.mkdir()
    monkeypatch.setenv("PATH", str(binaries) + ":" + os.environ["PATH"])
    command = [
        sys.executable,
        admin.__file__,
        "--state",
        str(stack.state),
        "--service",
        stack.service,
        "--image",
        stack.image,
        "--url",
        "http://manager.example.test",
        "--connect-to",
        "manager.example.test:80:" + stack.manager.removeprefix("http://"),
    ]
    service = binaries / "systemctl"
    service.write_text(
        '#!/usr/bin/env bash\nset -e\n[[ $2 == restart ]]\npodman stop "$3" >/dev/null\n'
        + shlex.join([*command, "recover"])
        + '\nexec podman start "$3" >/dev/null\n'
    )
    service.chmod(0o755)

    def invoke(action, value=None, success=True):
        result = subprocess.run(
            [*command, action],
            input=json.dumps(value) if value is not None else "",
            text=True,
            capture_output=True,
        )
        assert (result.returncode == 0) == success, result.stderr
        assert "n" * 48 not in result.stdout + result.stderr
        return result

    return invoke


def test_authentication_and_private_manager(stack):
    assert get(stack.api + "/v1/models")[0] == 401
    assert get(stack.api + "/v1/models", stack.api_key)[0] == 200
    for resource in ["capabilities", "usage", "well-known"]:
        url = stack.api + "/v0/resource/plugins/pi-bridge/" + resource
        assert get(url)[0] == 401
        status, body = get(url, stack.api_key)
        assert status == 200
        assert isinstance(json.loads(body), dict)
    assert get(stack.manager + "/v0/management/config")[0] == 401
    assert get(stack.manager + "/v0/management/config", stack.api_key)[0] == 401
    assert get(stack.manager + "/v0/management/config", stack.admin_key)[0] == 200
    with urllib.request.urlopen(stack.manager + "/") as response:
        assert response.url.endswith("/management.html")
        assert b"<html" in response.read()


def test_key_delivery_is_idempotent_and_preserves_configuration(stack):
    before = json.loads(get(stack.manager + "/v0/management/config", stack.admin_key)[1])
    key = "integration-new-cli-proxy-api-key"
    assert get(stack.api + "/v1/models", key)[0] == 401
    for _ in range(2):
        deploy_key(key, stack.admin_key, stack.manager, stack.api)
    after = json.loads(get(stack.manager + "/v0/management/config", stack.admin_key)[1])
    assert after.pop("api-keys") == [stack.api_key, key]
    before.pop("api-keys")
    assert after == before
    assert get(stack.api + "/v1/models", stack.api_key)[0] == 200
    assert get(stack.api + "/v1/models", key)[0] == 200


def test_admin_reset_recovers_without_bao_or_database_rollback(stack, admin_command):
    key = "n" * 48
    candidate = {"generation": 1, "admin_key": key}
    admin_command("stage", candidate)
    admin_command("stage", candidate)
    admin_command("stage", {"generation": 1, "admin_key": "x" * 48}, success=False)
    podman("stop", stack.service)
    admin_command("recover")
    admin_command("recover")
    podman("start", stack.service)
    admin_command("verify")
    admin_command("reconcile")
    assert get(stack.manager + "/status", stack.admin_key)[0] == 401
    assert get(stack.manager + "/status", key)[0] == 200
    assert (stack.state / "manager/admin-key").read_text().strip() == key
    assert (stack.state / "manager/admin-key").stat().st_mode & 0o777 == 0o600
    assert get(stack.api + "/v1/models", stack.api_key)[0] == 200
    assert get(stack.api + "/v0/resource/plugins/pi-bridge/capabilities", stack.api_key)[0] == 200
    admin_command("stage", {"generation": 2, "admin_key": "f" * 48}, success=False)
    admin_command("commit", {"generation": 1})
    admin_command("stage", {"generation": 2, "admin_key": "f" * 48})
    fault = stack.state / "test-bin/podman"
    fault.write_text(
        "#!/usr/bin/env bash\n[[ $1 != run ]] || exit 42\n"
        + "exec "
        + shlex.quote(shutil.which("podman"))
        + ' "$@"\n'
    )
    fault.chmod(0o755)
    admin_command("reconcile", success=False)
    assert get(stack.api + "/v1/models", stack.api_key)[0] == 200
    fault.unlink()
    admin_command("reconcile")
    admin_command("commit", {"generation": 2})
    admin_command("stage", candidate, success=False)
    assert get(stack.manager + "/status", key)[0] == 401
    assert get(stack.manager + "/status", "f" * 48)[0] == 200
