import fcntl
import json
import sqlite3
import subprocess
import sys
import tarfile
import time
from pathlib import Path

import pytest


@pytest.fixture
def backup_state(tmp_path):
    state = tmp_path / "state"
    manager = state / "manager"
    manager.mkdir(parents=True)
    (manager / "admin-key").write_text("test-admin-key\n")
    (manager / "data.key").write_text("test-data-key\n")
    (state / "admin-rotation.json").write_text(
        json.dumps({"generation": 3, "admin_key": "test-admin-key", "published": True})
    )
    (state / "config.yaml").write_text("test-config\n")
    (state / "auth").mkdir()
    (state / "auth/provider.json").write_text('{"token": "test-oauth-token"}')
    database = sqlite3.connect(manager / "usage.sqlite")
    database.execute("PRAGMA journal_mode=WAL")
    database.execute("PRAGMA wal_autocheckpoint=0")
    database.execute("CREATE TABLE usage (requests INTEGER)")
    database.execute("INSERT INTO usage VALUES (37)")
    database.commit()
    yield state, tmp_path / "backup.tar"
    database.close()


def command(state, destination):
    return [sys.executable, "-m", "cli_proxy_api.backup", str(state), str(destination)]


@pytest.fixture(autouse=True)
def package_path(monkeypatch):
    monkeypatch.setenv("PYTHONPATH", str(Path(__file__).parents[1] / "src"))


def test_backup_restores_wal_data_and_credentials_together(backup_state, tmp_path):
    state, destination = backup_state
    assert (state / "manager/usage.sqlite-wal").stat().st_size > 0
    subprocess.run(command(state, destination), check=True, capture_output=True)

    restored = tmp_path / "restored"
    with tarfile.open(destination) as archive:
        names = archive.getnames()
        assert "manager/usage.sqlite" in names
        assert not any(name.endswith(("-wal", "-shm", "-journal", ".lock")) for name in names)
        archive.extractall(restored, filter="data")
    with sqlite3.connect(restored / "manager/usage.sqlite") as database:
        assert database.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert database.execute("SELECT requests FROM usage").fetchall() == [(37,)]
    assert (restored / "manager/admin-key").read_text() == "test-admin-key\n"
    assert (restored / "manager/data.key").read_text() == "test-data-key\n"
    assert json.loads((restored / "admin-rotation.json").read_text())["generation"] == 3
    assert (restored / "config.yaml").read_text() == "test-config\n"
    assert json.loads((restored / "auth/provider.json").read_text())["token"] == "test-oauth-token"
    assert destination.stat().st_mode & 0o777 == 0o600


@pytest.mark.parametrize("missing", ["admin-key", "data.key", "usage.sqlite"])
def test_incomplete_state_preserves_previous_backup(backup_state, missing):
    state, destination = backup_state
    subprocess.run(command(state, destination), check=True, capture_output=True)
    previous = destination.read_bytes()
    (state / "manager" / missing).unlink()
    result = subprocess.run(command(state, destination), capture_output=True, text=True)
    assert result.returncode == 1
    assert "test-admin-key" not in result.stderr
    assert destination.read_bytes() == previous
    assert not list(destination.parent.glob(".cli-proxy-api-*"))


@pytest.mark.parametrize("lock_name", ["admin-rotation.lock", "admin-recovery.lock"])
def test_backup_waits_for_admin_maintenance(backup_state, lock_name):
    state, destination = backup_state
    with (state / lock_name).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with subprocess.Popen(
            command(state, destination), stdout=subprocess.PIPE, stderr=subprocess.PIPE
        ) as process:
            try:
                deadline = time.monotonic() + 5
                while not any(
                    "->" in line and f" {process.pid} " in line
                    for line in Path("/proc/locks").read_text().splitlines()
                ):
                    assert process.poll() is None, "Backup did not wait for maintenance"
                    assert time.monotonic() < deadline, "Backup did not reach the maintenance lock"
                    time.sleep(0.01)
                (state / "manager/admin-key").write_text("updated-admin-key\n")
                fcntl.flock(lock, fcntl.LOCK_UN)
                _, stderr = process.communicate(timeout=5)
                assert process.returncode == 0, stderr
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    with tarfile.open(destination) as archive:
        assert archive.extractfile("manager/admin-key").read() == b"updated-admin-key\n"
