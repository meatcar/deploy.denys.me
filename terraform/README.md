# Terraform

Each directory below is an independent state root. Use the repository's pinned
tooling and review a saved plan before applying it.

| Root | Owns |
| --- | --- |
| `terraform/` | Cloudflare DNS and CPA TLS rule, DigitalOcean, OCI, and existing AWS infrastructure |
| `terraform/bao` | OpenBao recovery infrastructure: AWS KMS, IAM, and backup bucket |
| `terraform/netbird` | Hosted NetBird groups, policies, peer settings, and private DNS |
| `terraform/ovh-vps` | Purchased OpenBao OVH VPS |
| `terraform/bao-config` | OpenBao API configuration: policies, auth, and project secrets |
| `terraform/railway` | Paseo service, domain, replicas, and non-secret variables |

See the [Terraform runbook](../docs/runbooks/terraform.md) for authentication,
planning, validation, and ownership boundaries. CLIProxyAPI key procedures are
in the [CLIProxyAPI runbook](../docs/runbooks/cli-proxy-api.md).

Do not run `nixos/systems/vpn/bootstrap.py`; hosted NetBird replaced that setup.
