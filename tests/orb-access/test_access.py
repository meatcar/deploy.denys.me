import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(os.environ.get("ORB_ACCESS_SOURCE", "templates/orb-access"))


class AccessTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in ("bin", "usr/bin", "etc/systemd/system", "run", "home/user"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        self.home = self.root / "home/user"
        self.project = self.home / "project"
        shutil.copytree(SOURCE, self.project, symlinks=True)
        self.bin = self.root / "tools"
        self.bin.mkdir()
        self.user_bin = self.root / "user-tools"
        self.user_bin.mkdir()
        # NOTE: Like sudo secure_path, root does not see user profile tools.
        self.stub("sudo", 'PATH="${PATH#/user-tools:}" exec "$@"')
        self.stub("direnv", 'if [ "$1" = exec ]; then shift 2; exec "$@"; fi')
        self.stub("systemctl", 'printf "%s\\n" "$*" >> /run/services')
        self.stub(
            "tofu",
            'test "$*" = "-chdir=terraform init -backend=false -input=false -lockfile=readonly"',
        )
        self.stub(
            "amp",
            'printf "%s\\n" "$*" >> /run/amp-calls; printf fixture-jwt; '
            'test "${AMP_FAIL:-}" != 1',
        )
        self.stub(
            "bao",
            """
test -z "${BAO_TOKEN:-}"
test "$*" = "write -format=json auth/amp/login role=fixture-role jwt=-"
test "$(cat)" = fixture-jwt
if [ "${LOGIN_FAIL:-}" = 1 ]; then exit 1; fi
if [ "${LOGIN_EMPTY:-}" = 1 ]; then printf '{}'; exit; fi
printf '{"auth":{"client_token":"fixture-bao-token"}}'
""",
        )
        self.stub(
            "netbird",
            """
if [ -n "${NETBIRD_SETUP_KEY:-}" ]; then touch /run/key-in-environment; exit 1; fi
printf '%s\\n' "$*" >> /run/netbird-calls
if [ "$3" = status ]; then
  if [ -e /run/connected ]; then
    printf '{"daemonStatus":"Connected","management":{"connected":true}}'
  else
    printf '{}'
  fi
elif [ "$3" = up ]; then
  shift 3
  test "$1" = --setup-key-file
  test "$(stat -c %a "$2")" = 600
  test "$(cat "$2")" = fixture-setup-key
  test -z "${NETBIRD_SETUP_KEY:-}"
  if [ "${ENROLL_FAIL:-}" = 1 ]; then exit 1; fi
  touch /run/connected
else
  exit 1
fi
""",
            directory=self.user_bin,
        )
        for name in ("env", "sh"):
            (self.root / ("usr/bin/env" if name == "env" else "bin/sh")).symlink_to(
                shutil.which("env" if name == "env" else "bash")
            )
        profile = self.home / ".nix-profile/bin"
        profile.mkdir(parents=True)
        (profile / "nix").symlink_to(shutil.which("true"))
        task = self.home / ".local/share/sandbox/task-v3.48.0/task"
        task.parent.mkdir(parents=True)
        task.symlink_to(shutil.which("task"))

    def stub(self, name, body, directory=None):
        file = (directory or self.bin) / name
        file.write_text(f"#!{shutil.which('bash')}\nset -euo pipefail\n{body}\n")
        file.chmod(0o755)

    def run_shell(self, command, *, success=True, **env):
        result = subprocess.run(
            [
                "bwrap",
                "--unshare-all",
                "--die-with-parent",
                "--bind",
                str(self.root),
                "/",
                "--ro-bind",
                "/nix/store",
                "/nix/store",
                "--proc",
                "/proc",
                "--dev",
                "/dev",
                "--tmpfs",
                "/tmp",
                "--chdir",
                "/home/user/project",
                "--clearenv",
                "--setenv",
                "HOME",
                "/home/user",
                "--setenv",
                "PATH",
                f"/user-tools:/tools:{os.environ['PATH']}",
                *[
                    item
                    for key, value in env.items()
                    for item in ("--setenv", key, value)
                ],
                "bash",
                "-ec",
                command,
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_bao_is_command_scoped_and_never_cached(self):
        result = self.run_shell(
            "task --dir . --taskfile .agents/Taskfile.yml access:bao -- bash -c "
            '\'test "$BAO_TOKEN" = fixture-bao-token; '
            'test "$NO_PROXY" = localhost,bao.vpn.denys.me; printf child-ok\'',
            BAO_ROLE="fixture-role",
            NO_PROXY="localhost",
            BAO_TOKEN="stale-token",
        )
        self.assertEqual(result.stdout, "child-ok")
        self.assertEqual(
            (self.root / "run/amp-calls").read_text().strip(),
            "orb id-token --audience bao --subject-scope project --ttl-seconds 300",
        )
        self.assertFalse((self.home / ".bao-token").exists())
        self.assertFalse((self.home / ".vault-token").exists())
        self.assertEqual(list((self.root / "run").glob("*token*")), [])
        for failure in ("LOGIN_FAIL", "LOGIN_EMPTY", "AMP_FAIL"):
            with self.subTest(failure=failure):
                self.run_shell(
                    "task --dir . --taskfile .agents/Taskfile.yml access:bao -- touch /run/consumer",
                    success=False,
                    BAO_ROLE="fixture-role",
                    **{failure: "1"},
                )
                self.assertFalse((self.root / "run/consumer").exists())

    def test_proxy_bypass_is_idempotent_and_keeps_the_egress_proxy(self):
        for env in ({"NO_PROXY": "localhost"}, {"no_proxy": "localhost"}):
            with self.subTest(env=env):
                result = self.run_shell(
                    "source .agents/access/env.sh; source .agents/access/env.sh; "
                    'test "$NO_PROXY" = "$no_proxy"; '
                    'test "$HTTPS_PROXY" = https://proxy.test; printf %s "$NO_PROXY"',
                    BAO_ADDR="https://private.example.test:443",
                    HTTPS_PROXY="https://proxy.test",
                    **env,
                )
                self.assertEqual(result.stdout, "localhost,private.example.test")

    def test_enrollment_is_file_only_and_resume_reuses_the_peer(self):
        result = self.run_shell(
            "bash .agents/access/netbird.sh resume",
            NETBIRD_SETUP_KEY="fixture-setup-key",
            AMP_THREAD_ID="T-fixture-123456789abc",
        )
        self.assertNotIn("fixture-setup-key", result.stdout + result.stderr)
        self.assertFalse((self.root / "run/key-in-environment").exists())
        calls = (self.root / "run/netbird-calls").read_text()
        self.assertIn(
            "--block-inbound --disable-client-routes --disable-server-routes", calls
        )
        self.assertIn("--hostname amp-orb-123456789abc", calls)
        self.assertNotIn("fixture-setup-key", calls)
        self.assertEqual(list((self.root / "run/amp-orb-access").iterdir()), [])
        self.run_shell("bash .agents/access/netbird.sh resume")
        self.assertEqual((self.root / "run/netbird-calls").read_text().count(" up "), 1)
        (self.root / "run/connected").unlink()
        self.run_shell("bash .agents/access/netbird.sh resume", success=False)
        self.run_shell(
            "bash .agents/access/netbird.sh resume",
            success=False,
            NETBIRD_SETUP_KEY="fixture-setup-key",
            ENROLL_FAIL="1",
        )
        self.assertEqual(list((self.root / "run/amp-orb-access").iterdir()), [])

    def test_setup_cleans_stale_identity_on_success_and_failure(self):
        for fail in (False, True):
            with self.subTest(fail=fail):
                for path in (
                    "run/amp-orb-netbird/default.json",
                    "run/amp-orb-access/setup-key.old",
                    "home/user/.bao-token",
                    "home/user/.vault-token",
                    "home/user/.aws/cli/cache/token.json",
                    "home/user/.aws/sso/cache/token.json",
                ):
                    file = self.root / path
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text("stale-fixture-identity")
                if fail:
                    self.stub("direnv", "exit 1")
                self.run_shell("bash .agents/setup", success=not fail)
                self.assertFalse((self.root / "run/amp-orb-netbird").exists())
                self.assertFalse((self.root / "run/amp-orb-access").exists())
                self.assertFalse((self.home / ".bao-token").exists())
                self.assertFalse((self.home / ".vault-token").exists())
                self.assertFalse((self.home / ".aws/cli/cache").exists())
                self.assertFalse((self.home / ".aws/sso/cache").exists())
                self.assertFalse((self.root / "run/amp-calls").exists())
                self.assertFalse((self.root / "run/netbird-calls").exists())
                self.assertIn(
                    "disable --now amp-orb-netbird.service",
                    (self.root / "run/services").read_text(),
                )

    def test_resume_only_connects_and_setup_is_repeatable(self):
        for _ in range(2):
            self.run_shell("bash .agents/setup")
        unit = (self.root / "etc/systemd/system/amp-orb-netbird.service").read_text()
        self.assertIn("Environment=NB_CONFIG=/run/amp-orb-netbird/default.json", unit)
        self.assertIn("Environment=NB_STATE_DIR=/run/amp-orb-netbird", unit)
        self.assertIn(
            "Environment=NB_DNS_STATE_FILE=/run/amp-orb-netbird/state.json", unit
        )
        self.assertIn("Environment=NB_USE_NETSTACK_MODE=false", unit)
        self.assertEqual(
            (self.home / ".bash_profile").read_text().count("# sandbox environment:"), 1
        )
        self.run_shell("bash .agents/resume", NETBIRD_SETUP_KEY="fixture-setup-key")
        self.run_shell("bash .agents/resume")
        self.assertFalse((self.root / "run/amp-calls").exists())
        self.run_shell(
            'bash -lc \'test "$NO_PROXY" = localhost,bao.vpn.denys.me; '
            'test "$no_proxy" = "$NO_PROXY"\'',
            NO_PROXY="localhost",
        )

    def test_cleanup_failure_fails_setup(self):
        self.stub("systemctl", 'if [ "$1" = disable ]; then exit 1; fi')
        self.run_shell("bash .agents/setup", success=False)


if __name__ == "__main__":
    unittest.main()
