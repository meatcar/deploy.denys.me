import pathlib
import subprocess
import sys
import tempfile
import unittest


HERE = pathlib.Path(__file__).parent


class LoopbackMigration(unittest.TestCase):
    def test_retains_mutable_configuration_and_is_idempotent(self):
        original = (HERE / "legacy.conf").read_bytes()
        expected = original.replace(
            b"    IPv6 = true\n", b"    IPv6 = false\n"
        ).replace(b"</Listener>", b"    Host = 127.0.0.1\n</Listener>")
        with tempfile.TemporaryDirectory() as directory:
            config = pathlib.Path(directory) / "znc.conf"
            config.write_bytes(original)
            config.chmod(0o640)
            command = [sys.executable, str(HERE / "loopback.py"), str(config), "6697"]
            result = subprocess.run(command, capture_output=True, check=True)
            self.assertEqual(result.stdout + result.stderr, b"")
            self.assertEqual(config.read_bytes(), expected)
            before = config.stat()
            subprocess.run(command, capture_output=True, check=True)
            self.assertEqual(config.read_bytes(), expected)
            after = config.stat()
            for field in ["st_ino", "st_mtime_ns", "st_mode", "st_uid", "st_gid"]:
                self.assertEqual(getattr(after, field), getattr(before, field))
            self.assertEqual(config.stat().st_mode & 0o777, 0o640)

    def test_existing_ipv6_binding_comments_and_non_listener_settings(self):
        original = b"""   /*
<Listener commented-out>
    Port = 6697
</Listener>
   */
   // A line comment with trailing whitespace\x20\x20
   < LiStEnEr listener0 >
\tPORT = 6697
\thost = ::
\tipv4 = false
\tipv6 = true
\tSSL = false
   < /lIsTeNeR >
<Listener unrelated>
    Port = 7667
    Host = ::1
</Listener>
<User retained>
    Host = 192.0.2.7
    QuitMsg = /* not a comment */
    LoadModule = alias http://fixture/#retained
</User>
""".replace(b"\n", b"\r\n")
        expected = original.replace(b"host = ::\r", b"host = 127.0.0.1\r")
        expected = expected.replace(b"ipv4 = false", b"ipv4 = true")
        expected = expected.replace(b"ipv6 = true", b"ipv6 = false")
        with tempfile.TemporaryDirectory() as directory:
            config = pathlib.Path(directory) / "znc.conf"
            config.write_bytes(original)
            subprocess.run(
                [sys.executable, str(HERE / "loopback.py"), str(config), "6697"],
                capture_output=True,
                check=True,
            )
            self.assertEqual(config.read_bytes(), expected)

    def test_refuses_ambiguous_or_malformed_configuration_without_logging_it(self):
        original = (HERE / "legacy.conf").read_bytes()
        invalid = [
            original.replace(b"6697", b"7667"),
            original + b"<Listener duplicate>\n    Port = 6697\n</Listener>\n",
            original.replace(b"Port = 6697", b"Port = 6697\n    PORT = 6697"),
            original.replace(b"</Listener>", b"</Different>"),
            original + b"/* unclosed comment\n",
            original.replace(b"Port = 6697", b"Port = private-fixture-value"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            config = pathlib.Path(directory) / "znc.conf"
            for data in invalid:
                with self.subTest(data=invalid.index(data)):
                    config.write_bytes(data)
                    result = subprocess.run(
                        [
                            sys.executable,
                            str(HERE / "loopback.py"),
                            str(config),
                            "6697",
                        ],
                        capture_output=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, b"")
                    self.assertEqual(
                        result.stderr,
                        b"ZNC loopback migration refused the persisted configuration\n",
                    )
                    self.assertEqual(config.read_bytes(), data)
                    self.assertEqual(list(config.parent.iterdir()), [config])


if __name__ == "__main__":
    unittest.main()
