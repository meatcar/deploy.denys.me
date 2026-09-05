import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

spec = importlib.util.spec_from_file_location(
    "backup", Path(__file__).with_name("backup.py")
)
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def test_each_role_backs_up_only_its_own_service(self):
        for role in ("vpn", "bao"):
            with (
                self.subTest(role=role),
                patch.object(backup.Path, "read_text", return_value=role),
                patch.object(backup, "snapshot_bao") as bao,
                patch.object(backup, "snapshot_netbird") as vpn,
            ):
                backup.main()
                self.assertEqual(bao.call_count, int(role == "bao"))
                self.assertEqual(vpn.call_count, int(role == "vpn"))

    def test_management_restarts_when_database_copy_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                patch.object(backup.subprocess, "run") as run,
                patch.object(
                    backup.shutil, "copytree", side_effect=OSError("disk full")
                ),
                self.assertRaises(OSError),
            ):
                backup.snapshot_netbird(Path(directory))
        self.assertEqual(
            run.call_args_list,
            [
                call(
                    ["systemctl", "stop", "podman-netbird-server.service"], check=True
                ),
                call(
                    ["systemctl", "start", "podman-netbird-server.service"], check=True
                ),
            ],
        )

    def test_unknown_role_fails_closed(self):
        with (
            patch.object(backup.Path, "read_text", return_value="other"),
            self.assertRaises(ValueError),
        ):
            backup.main()


if __name__ == "__main__":
    unittest.main()
