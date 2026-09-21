# Terraform

[Plan and apply with Terragrunt](../docs/runbooks/terraform.md).
Each entry is an independent state root.

| Root | Owns |
| --- | --- |
| `terraform/` | Cloudflare DNS and CPA TLS rule, DigitalOcean, OCI, and existing AWS infrastructure |
| `terraform/bao` | OpenBao recovery infrastructure: AWS KMS, IAM, and backup bucket |
| `terraform/netbird` | Hosted NetBird groups, policies, peer settings, and private DNS |
| `terraform/ovh-vps` | Purchased OpenBao OVH VPS |
| `terraform/bao-config` | OpenBao API configuration: policies, auth, and project secrets |
| `terraform/railway` | Paseo, RSSHub, and monitoring projects, services, volumes, and domains |

CLIProxyAPI key procedures are in the [service runbook](../docs/runbooks/cli-proxy-api.md).
