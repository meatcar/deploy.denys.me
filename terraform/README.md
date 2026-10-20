# Infrastructure

The live configuration uses the two state roots below. The one-time
[state migration](migrations/README.md) completed on 2026-09-22.
Do not apply pre-consolidation checkouts against these backends.

## Plan and apply

From the [repository environment](../README.md#setup), select one state root:

```sh
tofu -chdir=terraform init -lockfile=readonly
tofu -chdir=terraform plan -out=change.tfplan
tofu -chdir=terraform show change.tfplan
tofu -chdir=terraform apply change.tfplan
```

Use `-chdir=terraform/bao-config` for Bao configuration. Terragrunt is only an
optional bulk runner: `terragrunt --working-dir terraform run --all -- plan`.
It orders infrastructure before Bao configuration; it does not activate NixOS.

- Plans contain secrets. Keep them private and ignored.
- Re-plan dependent states after upstream changes. There is no shared rollback.
- Bulk apply approves individual units automatically.
- NixOS activation is separate. See [deploy.nix](../flake-parts/deploy.nix).

| State root | Owns |
| --- | --- |
| `terraform/` | Hosts, public/private DNS, VPN access, AWS support, Railway workloads |
| `terraform/bao-config` | OpenBao auth, policies, project secrets |

Native child modules in `modules/` organize related resources without adding
states. Provider configuration belongs in the root. Bao configuration stays
separate because its provider requires a running, reachable Bao instance.

### Agent plans

In an enrolled Amp orb, run from the repository root:

```sh
direnv exec . task --taskfile .agents/Taskfile.yml plan
```

The task logs into Bao on demand, mints a project-scoped AWS web identity for
`arn:aws:iam::148676508643:role/tofu-plan` with audience
`urn:amp:aws:tofu-plan:148676508643`, and reads the KV v2 documents below from
mount `projects/meatcar/deploy.denys.me`. Every field must be a nonempty string;
missing documents, missing fields, or extra fields stop the task before init.

| Document | Required fields |
| --- | --- |
| `prod/plan/digitalocean` | `TF_VAR_digitalocean_token` |
| `prod/plan/ovh` | `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` |

The plan covers only resources whose providers have a read-only credential that
cannot read secrets:

```sh
tofu -chdir=terraform plan -input=false -lock=false \
  -target=module.state -target=module.bao_support -target=module.aws_plan_access \
  -target=digitalocean_droplet.www -target=ovh_vps.bao
```

Cloudflare, NetBird, OCI, and Railway stay out: their read access exposes
object contents, SQL, logs, instance metadata, or owner authority. Targeting
prunes their providers, so the task sets `TF_VAR_cloudflare_token` and
`TF_VAR_oci_region` to empty strings and supplies no credentials for them. Add a
target only together with a verified read-only credential for its provider.

Supply the non-secret root inputs through tfvars or their `TF_VAR_*` variables.
The task passes only declared non-secret root inputs and runtime settings such
as proxies and CA paths. It ignores inherited provider credentials, AWS
profiles, Terraform CLI arguments, and debug logging. It never falls back to
operator credentials or writes a saved plan.

Setup caches providers with `init -backend=false`; resume does not run init.
The plan task runs `init -reconfigure -input=false -lockfile=readonly` with only
the AWS role identity, then gives provider credentials only to the plan process.
Bao tokens and provider values stay in memory. The AWS token and isolated HOME
are private temporary files removed on success, failure, or handled signals.
SIGKILL or loss of the orb can prevent cleanup; do not snapshot a running plan.
No Bao/Vault login or AWS session cache is saved.

To cut agent access at once, run as an operator. Applying the main root and
`terraform/bao-config` restores it.

```sh
bao delete auth/amp/role/project--meatcar--deploy.denys.me--prod--plan--read
aws iam delete-role-policy --role-name tofu-plan --policy-name main-root-refresh
```

Also revoke the setup key in NetBird; the static `NETBIRD_SETUP_KEY` enrolls
new orbs into `amp--orbs`. Amp-side identity revocation can lag up to 24 hours.

Run only the main root, never the Terragrunt bulk runner or
`terraform/bao-config`, whose plans read CLIProxyAPI secrets.

This is a preview, not a drift check or a plan to apply. Treat anything an agent
can read as disclosed. Before applying, an operator must create and review a
fresh, unrestricted plan. Targets are not a security boundary; provider
permissions and restricted state/Bao access are.

## Access

Put credentials in `.env`. Names are in [.env.example](../.env.example).
Keep secrets out of HCL, tfvars, history, and debug logs.

- AWS and Bao use SSO: `aws sso login --profile "$AWS_PROFILE"`.
- Bao also requires NetBird connectivity.
- OCI: `oci session authenticate --profile-name meatcar --session-expiration-in-minutes 60`.
  Set `TF_VAR_oci_region` and `TF_VAR_oci_compartment_ocid` for the target compartment.
  `TF_VAR_oci_auth` defaults to `SecurityToken`. For a read-only API-key user, set
  it to `APIKey` and select that user's OCI config profile with
  `TF_VAR_oci_config_file_profile`, which otherwise defaults to `meatcar`.

## Before changing resources

| Area | Constraint |
| --- | --- |
| State backend | Owned by `module.state` in the main root. Never apply `modules/terraform-state` separately against this account. |
| OpenBao | Keep bootstrap infrastructure independent of `bao-config`. Preserve SSO trust and userpass recovery. Never reinitialize the database. |
| NetBird | Check peer IDs and complete group memberships. Broad policies can bypass narrow ones. Preserve Tailscale coexistence. |
| NetBird DNS | Avoid overlapping `vpn.denys.me` zones. Test DNS, TLS, and authentication from affected clients. |
| CLIProxyAPI ports | Keep TCP 443 and 9443. NetBird filters both sides of the host redirect. |
| OVH | Keep `plan = []`. Purchase, image, SSH-key, and plan-option changes can reinstall the VPS. NixOS owns its OS and keys. |
| Railway | Service and variable updates redeploy workloads. Removing a nested volume deletes data despite service-level `prevent_destroy`. |
| Railway adoption | Imports only. Declare intended non-secret variables. Leave unreadable or unsupported settings Railway-managed. |

`prevent_destroy` does not block in-place access-policy changes.
For OVH, prefer API access limited to `GET /auth/details` and the target VPS's GET endpoint.

Recovery and credentials: [OpenBao](../nixos/systems/bao/README.md),
[CLIProxyAPI](../packages/cli-proxy-api/README.md).
Relay clients and deployment: [Paseo](../nixos/modules/quadlets/paseo-relay/README.md).

## Checks

[Flake checks](../README.md#workflow) use mocked providers and a pinned mirror.
They do not validate live plans. After provider-lock changes, update mirror hashes
in [checks.nix](checks.nix) from Nix's hash-mismatch output.
