import json
import shlex
from types import SimpleNamespace

import pytest

from cli_proxy_api import admin, backup, deploy_key, initialize, rotate_admin
from cli_proxy_api.deployment import Deployment


@pytest.mark.parametrize("command", [admin, backup, deploy_key, initialize, rotate_admin])
def test_help_is_safe_without_credentials(command, monkeypatch, tmp_path, capsys):
    monkeypatch.delenv("CLI_PROXY_API_KEY", raising=False)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr("sys.argv", [command.__name__, "--help"])
    with pytest.raises(SystemExit) as result:
        command.main()
    assert result.value.code == 0
    assert "usage:" in capsys.readouterr().out
    assert not list(tmp_path.iterdir())


def test_profile_selects_endpoints_and_quotes_remote_paths(tmp_path, monkeypatch):
    path = tmp_path / "deployment.json"
    path.write_text(
        json.dumps(
            {
                "ssh_host": "other-host.example.test",
                "service_user": "application",
                "runtime_directory": "/run/user/3456",
                "state_directory": "/srv/client's application",
                "public_host": "api.example.test",
                "management_host": "admin.example.test",
                "secret_mount": "applications",
                "inference_secret_path": "customer/staging/inference",
                "admin_secret_path": "customer/staging/admin",
            }
        )
    )
    calls = []

    def ssh(command, **kwargs):
        calls.append((command, kwargs))
        return SimpleNamespace(stdout="test-admin-key\n")

    deployed = []
    monkeypatch.setattr("cli_proxy_api.deployment.subprocess.run", ssh)
    monkeypatch.setattr(deploy_key, "deploy_key", lambda *args: deployed.append(args))
    monkeypatch.setenv("CLI_PROXY_API_KEY", "test-inference-key")
    monkeypatch.setenv("CLI_PROXY_API_CONFIG", "/wrong/profile.json")
    monkeypatch.setattr("sys.argv", ["deploy-key", "--config", str(path)])
    deploy_key.main()
    command, _ = calls.pop()
    assert command[:-1] == [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "--",
        "other-host.example.test",
    ]
    assert shlex.split(command[-1]) == [
        "sudo",
        "-n",
        "cat",
        "--",
        "/srv/client's application/manager/admin-key",
    ]
    assert deployed == [
        (
            "test-inference-key",
            "test-admin-key",
            "https://admin.example.test",
            "https://api.example.test",
        )
    ]

    Deployment.load(path).rotate_admin("stage", {"admin_key": "test-secret"})
    command, kwargs = calls.pop()
    assert shlex.split(command[-1]) == [
        "sudo",
        "-n",
        "-u",
        "application",
        "env",
        "XDG_RUNTIME_DIR=/run/user/3456",
        "cli-proxy-api-admin",
        "stage",
    ]
    assert json.loads(kwargs["input"]) == {"admin_key": "test-secret"}
    assert "test-secret" not in str(command)
