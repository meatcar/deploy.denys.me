import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "bootstrap", Path(__file__).with_name("bootstrap.py")
)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def test_private_atomic_write(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "credentials"
            bootstrap.write_private(path, "first")
            bootstrap.write_private(path, "second")
            self.assertEqual(path.read_text(), "second")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertFalse(path.with_suffix(".tmp").exists())

    def test_completed_bao_bootstrap_does_not_need_revoked_root(self):
        with tempfile.TemporaryDirectory() as directory:
            etc = Path(directory)
            (etc / "bao-configured").write_text("configured")
            (etc / "openbao-initialization.json").write_text(
                json.dumps({"recovery_keys_base64": ["test-only"]})
            )
            (etc / "restic-password").write_text("test-only")
            with (
                patch.object(bootstrap, "ETC", etc),
                patch.object(bootstrap, "request", return_value={"initialized": True}),
                patch.object(bootstrap, "command"),
            ):
                result = bootstrap.initialize_bao({})
            self.assertEqual(result["recovery_keys_b64"], ["test-only"])
            self.assertNotIn("root_token", result)

    def test_prepare_preserves_datastore_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            etc = Path(directory) / "etc"
            data = {
                "backup": {},
                "repository": "test-only",
            }
            with (
                patch.object(bootstrap, "STATE", state),
                patch.object(bootstrap, "ETC", etc),
                patch.object(bootstrap, "host_role", return_value="vpn"),
                patch.object(bootstrap, "command"),
            ):
                bootstrap.prepare(data)
                first = (state / "config.json").read_text()
                password = (etc / "restic-password").read_text()
                bootstrap.prepare(data)
            self.assertEqual((state / "config.json").read_text(), first)
            self.assertEqual((etc / "restic-password").read_text(), password)

    def test_resume_after_root_revocation(self):
        with tempfile.TemporaryDirectory() as directory:
            etc = Path(directory)
            recovery = etc / "openbao-initialization.json"
            recovery.write_text(
                json.dumps({"root_token": "revoked", "recovery_keys_base64": ["share"]})
            )
            (etc / "restic-password").write_text("test-only")
            (etc / "bao-backup-token").write_text("test-only")

            def request(url, path, method="GET", payload=None, token=None):
                if path == "/sys/init":
                    return {"initialized": True}
                if path == "/auth/token/lookup-self":
                    raise bootstrap.urllib.error.HTTPError(
                        url, 403, "revoked", {}, None
                    )
                if path == "/auth/userpass/login/denys":
                    return {"auth": {"client_token": "replacement"}}
                if token is not None:
                    self.assertEqual(token, "replacement")
                self.assertNotIn(path, ("/sys/audit/file", "/sys/auth/userpass"))
                return {"data": {"file/": {}, "userpass/": {}}}

            with (
                patch.object(bootstrap, "ETC", etc),
                patch.object(bootstrap, "request", side_effect=request),
                patch.object(bootstrap, "command"),
            ):
                result = bootstrap.initialize_bao({"password": "test-only"})
            self.assertEqual(result["recovery_keys_b64"], ["share"])
            self.assertNotIn("root_token", json.loads(recovery.read_text()))
            self.assertTrue((etc / "bao-configured").exists())

    def test_private_dns_uses_enrolled_ip_and_requires_server_group(self):
        for member in (True, False):
            with (
                self.subTest(member=member),
                tempfile.TemporaryDirectory() as directory,
            ):
                etc = Path(directory)
                (etc / "bootstrap-pat").write_text("test-only")
                (etc / "proxy.env").write_text("test-only")
                (etc / "restic-password").write_text("test-only")
                records = []

                def request(base, path, method="GET", payload=None, token=None):
                    if path == "/instance":
                        return {"setup_required": False}
                    if path == "/groups":
                        return [
                            {"name": "bao-admins", "id": "admins", "peers": []},
                            {
                                "name": "bao-server",
                                "id": "server",
                                "peers": [{"id": "right"}] if member else [],
                            },
                        ]
                    if path == "/policies":
                        return [{"name": "bao-admin-access"}]
                    if path == "/peers":
                        return [
                            {
                                "id": "wrong",
                                "name": "bao",
                                "ip": "100.64.0.9",
                                "connected": True,
                            },
                            {
                                "id": "right",
                                "name": "other",
                                "ip": "100.64.0.2",
                                "connected": True,
                            },
                        ]
                    if path == "/peers/right":
                        return None
                    if path == "/dns/zones":
                        return [] if method == "GET" else {"id": "zone"}
                    if path == "/dns/zones/zone/records":
                        if method == "POST":
                            records.append(payload)
                        return []
                    raise AssertionError(path)

                with (
                    patch.object(bootstrap, "ETC", etc),
                    patch.object(bootstrap, "request", side_effect=request),
                    patch.object(bootstrap, "command"),
                ):
                    if member:
                        result = bootstrap.netbird({"peer_ip": "100.64.0.2"})
                        self.assertEqual(result["peer_ip"], "100.64.0.2")
                        self.assertEqual(records[0]["content"], "100.64.0.2")
                    else:
                        with self.assertRaisesRegex(RuntimeError, "server group"):
                            bootstrap.netbird({"peer_ip": "100.64.0.2"})
                        self.assertEqual(records, [])

    def test_reject_multiline_environment(self):
        with (
            patch.object(bootstrap, "host_role", return_value="vpn"),
            self.assertRaises(ValueError),
        ):
            bootstrap.prepare(
                {
                    "backup": {"AWS_SECRET_ACCESS_KEY": "value\nOTHER=bad"},
                    "repository": "test",
                }
            )

    def test_public_host_rejects_bao_credentials_before_writing(self):
        with (
            patch.object(bootstrap, "host_role", return_value="vpn"),
            patch.object(bootstrap, "write_private") as write,
            self.assertRaisesRegex(ValueError, "host's role"),
        ):
            bootstrap.prepare(
                {"backup": {}, "repository": "test", "openbao": {}, "acme": {}}
            )
        write.assert_not_called()

    def test_bao_prepare_does_not_create_management_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            state, etc = Path(directory) / "state", Path(directory) / "etc"
            with (
                patch.object(bootstrap, "host_role", return_value="bao"),
                patch.object(bootstrap, "STATE", state),
                patch.object(bootstrap, "ETC", etc),
                patch.object(bootstrap, "command") as command,
            ):
                bootstrap.prepare(
                    {"openbao": {}, "backup": {}, "acme": {}, "repository": "test"}
                )
            self.assertFalse((state / "config.json").exists())
            self.assertTrue((etc / "openbao.env").exists())
            command.assert_called_once_with(
                "systemctl", "restart", "acme-bao.vpn.denys.me.service"
            )

    def test_enrollment_reports_local_overlay_ip_and_removes_key(self):
        with tempfile.TemporaryDirectory() as directory:
            etc = Path(directory)
            with (
                patch.object(bootstrap, "ETC", etc),
                patch.object(
                    bootstrap,
                    "command",
                    side_effect=["", '{"netbirdIp":"100.64.0.2/16"}'],
                ) as command,
            ):
                self.assertEqual(
                    bootstrap.enroll({"key": "test"}), {"peer_ip": "100.64.0.2"}
                )
                self.assertEqual(
                    command.call_args_list[0].args,
                    (
                        "netbird",
                        "up",
                        "--management-url",
                        "https://api.netbird.io:443",
                        "--hostname",
                        "bao",
                    ),
                )
            self.assertFalse((etc / "setup-key").exists())


if __name__ == "__main__":
    unittest.main()
