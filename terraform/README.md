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

Agents plan from the repository root with only verified read-only provider
credentials:

```sh
TF_VAR_oci_auth=APIKey tofu -chdir=terraform plan \
  -input=false -lock=false -exclude=module.railway_services
```

Railway has no read-only token. Exclude its whole module and do not supply a
Railway token. Run only the main root, never the Terragrunt bulk runner or
`terraform/bao-config`, whose plans read CLIProxyAPI secrets. Bao configuration
is a separate state, not a module to exclude from this command.

This partial plan omits Railway and anything depending on it. It is not a full
drift check or a plan to apply. Before applying, an operator must create and
review a fresh, unrestricted plan with the appropriate credentials. These flags
are not a security boundary; provider permissions and restricted state/Bao access
are.

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
