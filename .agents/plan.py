import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


DOCUMENT_FIELDS = {
    "digitalocean": ("TF_VAR_digitalocean_token",),
    "ovh": ("OVH_APPLICATION_KEY", "OVH_APPLICATION_SECRET", "OVH_CONSUMER_KEY"),
}
TARGETS = (
    "module.state",
    "module.bao_support",
    "module.aws_plan_access",
    "digitalocean_droplet.www",
    "ovh_vps.bao",
)
# NOTE: Targeting prunes these providers; root variables still need values.
UNUSED_VARIABLES = ("TF_VAR_cloudflare_token", "TF_VAR_oci_region")


def read_document(provider, fields):
    result = subprocess.run(
        [
            "bao",
            "kv",
            "get",
            "-format=json",
            "-mount=projects/meatcar/deploy.denys.me",
            f"prod/plan/{provider}",
        ],
        capture_output=True,
        text=True,
    )
    try:
        if result.returncode:
            raise ValueError
        data = json.loads(result.stdout)["data"]["data"]
        if (
            not isinstance(data, dict)
            or set(data) != set(fields)
            or any(
                not isinstance(value, str) or not value.strip() or "\0" in value
                for value in data.values()
            )
        ):
            raise ValueError
    except (ValueError, KeyError, TypeError):
        sys.exit(f"Missing or invalid plan credential document: {provider}")
    return data


def main():
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="tofu-plan-") as directory:
        home = Path(directory)
        token = home / "aws-token"
        token_env = {
            k: v for k, v in os.environ.items() if k not in {"BAO_TOKEN", "VAULT_TOKEN"}
        }
        with token.open("w") as output:
            result = subprocess.run(
                [
                    "amp",
                    "orb",
                    "id-token",
                    "--audience",
                    "urn:amp:aws:tofu-plan:148676508643",
                    "--subject-scope",
                    "project",
                    "--ttl-seconds",
                    "300",
                ],
                env=token_env,
                stdout=output,
                stderr=subprocess.DEVNULL,
            )
        if result.returncode or not token.stat().st_size:
            sys.exit("Could not mint the AWS plan identity")

        documents = {
            provider: read_document(provider, fields)
            for provider, fields in DOCUMENT_FIELDS.items()
        }
        passthrough = {
            "PATH",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy",
            "SSL_CERT_FILE",
            "SSL_CERT_DIR",
            "NIX_SSL_CERT_FILE",
            "LANG",
            "LC_ALL",
            "TERM",
            "TF_PLUGIN_CACHE_DIR",
            "TF_VAR_ssh_fingerprint",
            "TF_VAR_cloudflare_account_id",
            "TF_VAR_cloudflare_domain",
            "TF_VAR_hostname",
            "TF_VAR_parked_domains",
            "TF_VAR_oci_compartment_ocid",
            "TF_VAR_private_server_ips",
            "TF_VAR_private_access_peer_ids",
            "TF_VAR_repository_root",
        }
        env = {k: v for k, v in os.environ.items() if k in passthrough}
        env.update(
            HOME=directory,
            AWS_ROLE_ARN="arn:aws:iam::148676508643:role/tofu-plan",
            AWS_WEB_IDENTITY_TOKEN_FILE=str(token),
            AWS_ROLE_SESSION_NAME="amp-tofu-plan",
            AWS_CONFIG_FILE="/dev/null",
            AWS_SHARED_CREDENTIALS_FILE="/dev/null",
            AWS_EC2_METADATA_DISABLED="true",
            TF_IN_AUTOMATION="1",
        )
        result = subprocess.run(
            [
                "tofu",
                "-chdir=terraform",
                "init",
                "-reconfigure",
                "-input=false",
                "-lockfile=readonly",
            ],
            env=env,
        )
        if result.returncode:
            return result.returncode

        for document in documents.values():
            env.update(document)
        env.update(dict.fromkeys(UNUSED_VARIABLES, ""))
        print(f"Partial plan, targets only: {', '.join(TARGETS)}", file=sys.stderr)
        return subprocess.run(
            [
                "tofu",
                "-chdir=terraform",
                "plan",
                "-input=false",
                "-lock=false",
                *(f"-target={target}" for target in TARGETS),
            ],
            env=env,
        ).returncode


def interrupted(signum, _frame):
    sys.exit(128 + signum)


if __name__ == "__main__":
    for termination_signal in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(termination_signal, interrupted)
    sys.exit(main())
