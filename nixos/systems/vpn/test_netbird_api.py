import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location(
    "bootstrap", Path(__file__).with_name("bootstrap.py")
)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


@unittest.skipUnless(
    os.environ.get("NETBIRD_INTEGRATION") == "1",
    "Set NETBIRD_INTEGRATION=1 to run a disposable local Podman server",
)
class NetBirdAPIIntegration(unittest.TestCase):
    def test_pinned_server_bootstrap_api(self):
        container = "vpn-api-test-" + uuid.uuid4().hex[:10]
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / "server").mkdir()
            with (
                patch.object(bootstrap, "STATE", state),
                patch.object(bootstrap, "ETC", state / "etc"),
                patch.object(bootstrap, "host_role", return_value="vpn"),
                patch.object(bootstrap, "command"),
            ):
                bootstrap.prepare({"backup": {}, "repository": "test-only"})
            try:
                subprocess.run(
                    [
                        "podman",
                        "run",
                        "-d",
                        "--name",
                        container,
                        "-p",
                        "127.0.0.1::80",
                        "-e",
                        "NB_SETUP_PAT_ENABLED=true",
                        "-v",
                        f"{state / 'config.json'}:/etc/netbird/config.yaml:ro",
                        "-v",
                        f"{state / 'server'}:/var/lib/netbird",
                        "docker.io/netbirdio/netbird-server:0.78.1@sha256:3086534361a18573b85897383a0753a97b8c75d68dee9926fbd7eccab1f2fe89",
                        "--config",
                        "/etc/netbird/config.yaml",
                    ],
                    check=True,
                    capture_output=True,
                )
                port = subprocess.check_output(
                    ["podman", "port", container, "80/tcp"], text=True
                ).strip()
                with (
                    patch.object(bootstrap, "NB_URL", "http://" + port + "/api"),
                    patch.object(bootstrap, "ETC", state / "etc"),
                ):
                    self.exercise_api()
            finally:
                subprocess.run(
                    ["podman", "rm", "-f", container], check=False, capture_output=True
                )

    def exercise_api(self):
        base = bootstrap.NB_URL
        bootstrap.wait_for(
            lambda: bootstrap.request(base, "/instance"), "Test server not ready"
        )
        setup = bootstrap.netbird(
            {
                "email": "test@example.com",
                "password": "test-only-disposable-password",
            },
        )
        token = (bootstrap.ETC / "bootstrap-pat").read_text()

        def api(path, method="GET", data=None):
            return bootstrap.request(base, path, method, data, token)

        groups = {group["name"]: group for group in api("/groups")}
        group = groups["bao-admins"]
        self.assertEqual(group["peers_count"], 0)
        self.assertEqual(groups["bao-server"]["peers_count"], 0)
        policies = {policy["name"]: policy for policy in api("/policies")}
        self.assertFalse(policies["Default"]["enabled"])
        rule = policies["bao-admin-access"]["rules"][0]
        self.assertEqual(rule["ports"], ["443"])
        self.assertEqual([g["id"] for g in rule["sources"]], [group["id"]])
        self.assertEqual(
            [g["id"] for g in rule["destinations"]], [groups["bao-server"]["id"]]
        )
        self.assertFalse(rule["bidirectional"])
        self.assertEqual(
            api("/setup-keys/" + setup["id"])["auto_groups"],
            [groups["bao-server"]["id"]],
        )
        bootstrap.revoke_setup({"id": setup["id"]})
        revoked = api("/setup-keys/" + setup["id"])
        self.assertTrue(revoked["revoked"])
        self.assertEqual(revoked["auto_groups"], [groups["bao-server"]["id"]])
        zone = api(
            "/dns/zones",
            "POST",
            {
                "name": "Private OpenBao",
                "domain": "bao.vpn.denys.me",
                "enabled": True,
                "enable_search_domain": False,
                "distribution_groups": [group["id"]],
            },
        )
        path = "/dns/zones/" + zone["id"] + "/records"
        api(
            path,
            "POST",
            {
                "name": "bao.vpn.denys.me",
                "type": "A",
                "content": "100.64.0.2",
                "ttl": 60,
            },
        )
        self.assertEqual(api(path)[0]["content"], "100.64.0.2")
        setup = api(
            "/setup-keys",
            "POST",
            {
                "name": "test",
                "type": "one-off",
                "expires_in": 86400,
                "auto_groups": [group["id"]],
                "usage_limit": 1,
            },
        )
        self.assertIn("key", setup)
        api(
            "/setup-keys/" + setup["id"],
            "PUT",
            {"revoked": True, "auto_groups": [group["id"]]},
        )


if __name__ == "__main__":
    unittest.main()
