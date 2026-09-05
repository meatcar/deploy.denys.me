import json
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Deployment:
    ssh_host: str
    service_user: str
    runtime_directory: str
    state_directory: str
    public_host: str
    management_host: str
    secret_mount: str
    inference_secret_path: str
    admin_secret_path: str

    @classmethod
    def load(cls, path):
        return cls(**json.loads(Path(path).read_text()))

    @property
    def management_url(self):
        return "https://" + self.management_host

    @property
    def api_url(self):
        return "https://" + self.public_host

    def ssh(self, *command, input="", timeout=30):
        return subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "--",
                self.ssh_host,
                shlex.join(command),
            ],
            input=input,
            text=True,
            capture_output=True,
            check=True,
            timeout=timeout,
        )

    def rotate_admin(self, action, value=None):
        command = (
            ["systemctl", "--user", "start", "cli-proxy-api-admin-rotate.service"]
            if action == "apply"
            else ["cli-proxy-api-admin", action]
        )
        self.ssh(
            "sudo",
            "-n",
            "-u",
            self.service_user,
            "env",
            "XDG_RUNTIME_DIR=" + self.runtime_directory,
            *command,
            input=json.dumps(value) if value is not None else "",
            timeout=330,
        )
