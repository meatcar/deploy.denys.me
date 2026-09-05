import json
import stat

from cli_proxy_api.initialize import initialize


def test_private_credentials_and_existing_configuration_survive_restart(tmp_path):
    path = tmp_path / "config.yaml"
    settings = {
        "port": 19283,
        "auth-dir": "/custom/auth",
        "remote-management": {"allow-remote": True},
        "plugins": {"enabled": False},
    }
    initialize(path, settings)
    config = json.loads(path.read_text())
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert len(config["api-keys"][0]) >= 43
    assert len(config["remote-management"]["secret-key"]) >= 43
    assert config["api-keys"][0] != config["remote-management"]["secret-key"]
    assert config["port"] == 19283
    assert config["auth-dir"] == "/custom/auth"
    assert config["remote-management"]["allow-remote"]
    assert config["plugins"] == {"enabled": False}
    assert "secret-key" not in settings["remote-management"]
    assert "api-keys" not in settings
    manager_key_path = tmp_path / "manager/admin-key"
    assert manager_key_path.read_text().startswith("cpamp_")
    assert stat.S_IMODE(manager_key_path.stat().st_mode) == 0o600
    key_path = tmp_path / "management-key"
    assert stat.S_IMODE(key_path.stat().st_mode) == 0o600
    assert key_path.read_text().strip() == config["remote-management"]["secret-key"]
    path.write_text("# operator-managed configuration\n")
    initialize(path, settings)
    assert path.read_text() == "# operator-managed configuration\n"
    path.unlink()
    initialize(path, settings)
    restored = json.loads(path.read_text())
    assert restored["remote-management"]["secret-key"] == config["remote-management"]["secret-key"]
    assert not path.with_name("config.pending").exists()
