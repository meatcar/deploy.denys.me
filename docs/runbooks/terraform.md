# Terraform operations

Load `.env` with direnv, then run commands in `nix develop`. Terragrunt uses
OpenTofu and preserves each root's existing S3 state. Plan all six units:

```sh
terragrunt --working-dir terraform run --all -- plan
```

From inside `terraform/`, use `terragrunt run --all -- plan`. Initialization is
automatic. For one unit, save, inspect, and approve its plan before applying:

```sh
terragrunt --working-dir terraform/netbird run -- plan -out=change.tfplan
terragrunt --working-dir terraform/netbird run -- show change.tfplan
terragrunt --working-dir terraform/netbird run -- apply change.tfplan
```

The main unit is `terraform/`; the others are `bao`, `bao-config`, `netbird`,
`ovh-vps`, and `railway`. `tf-modules/terraform-state` is a child module, not a
Terragrunt unit. Bao configuration runs after `bao` and `netbird`; host
deployment remains separate. Use deploy-rs for configured hosts, for example
`deploy .#chunkymonkey`.

To save all plans, add `--out-dir "$PWD/output/plans"` before `-- plan`, running
from the repository root. Plans can contain secrets; keep that directory private
and ignored. Bulk apply automatically approves individual units. Prefer reviewed
single-unit applies; re-plan dependents after upstream changes. There is no
cross-state transaction or automatic rollback.

Use the current AWS profile and `aws sso login --profile "$AWS_PROFILE"` for
backend access. OpenBao's Terraform provider also uses that SSO session. The
Bao 2.5.4 CLI cannot log in with AWS; use userpass for CLI work.

## Hosted NetBird

Set `NB_PAT` in the environment. Never put it in HCL, tfvars, shell history, or
command output. Before changing `terraform/netbird`, verify live peer IDs,
complete group membership, policies, and DNS in the hosted account. Peer names
are not identities.

Keep `bao-server` limited to the Bao peer and preserve every approved
`bao-admins` and `cpa-admins` member. Review account-wide policies because they
can bypass narrower service policies. The CPA policy needs TCP 443 and 9443:
NetBird filters both before and after the host redirect. It grants no SSH.

Private CPA DNS must resolve `cpa.vpn.denys.me` to the enrolled server. Clients
must accept NetBird DNS. Do not create an overlapping `vpn.denys.me` zone.
Tailscale remains operational; NetBird changes must not remove or replace it.

Provider IDs and complete memberships live in `terraform/netbird/terragrunt.hcl`.
Do not pass the old `adoption.tfvars`; it would override those inputs.
Never use a broad apply to fix an import error.
`prevent_destroy` does not prevent an in-place membership or policy change.

## Purchased OVH VPS

`terraform/ovh-vps` owns the purchased VPS record.

Supply `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, and
`OVH_CONSUMER_KEY` through the environment. Scope credentials to
`GET /auth/details` and `GET /vps/vps-5c07e980.vps.ovh.ca` where possible.
Keep `plan = []`; changing purchase, image, SSH-key, or plan-option fields can
reinstall the server or alter its service. NixOS owns the OS and SSH keys.

## OpenBao configuration

Reach `https://bao.vpn.denys.me` through NetBird. Normal Terraform plans
use AWS SSO. Keep the existing userpass account for recovery. Do not replace the
auth mount or loosen the exact trusted AWS SSO role to a wildcard.

OpenBao bootstrap is complete. Do not rerun `initialize_bao`, recreate the AWS
auth setup, or reinitialize the database. The backup token, password, recovery
shares, runtime IAM keys, and application passwords stay outside Terraform.
See the [Bao host runbook](../../nixos/systems/bao/README.md) for first-install
and recovery procedures.

## Railway

Set `RAILWAY_TOKEN` in the environment. `terraform/railway` declares:

- Paseo: project, production service, domain, replicas, and listed non-secret variables.
- RSSHub: project, RSSHub and Redis services, Redis volume, and Railway domain.
- Monitoring: project, Uptime Kuma and MySQL services, both volumes, and `monitor.denys.me`.

Project and service IDs are in `terraform/railway/terragrunt.hcl`; `imports.tf`
adopts the existing resources. The adoption plan must contain imports only,
with no creates, updates, or deletes. Review it before applying:

```sh
terragrunt --working-dir terraform/railway run -- plan -out=railway.tfplan
terragrunt --working-dir terraform/railway run -- apply railway.tfplan
```

Service and variable updates redeploy workloads and require deployment approval.
Never remove a service's nested `volume` to relinquish ownership: the provider
deletes its data during an update, even with service-level `prevent_destroy`.

RSSHub's existing repository connection has no branch trigger readable by the
provider. Its source connection stays Railway-managed. New services retain
their existing computed regions and replicas. Secret variables, volume sizes,
health checks, restart policies, serverless mode, and CPU/memory limits also
stay Railway-managed. See the [Paseo runbook](../../railway/paseo-relay/README.md)
for its remaining service settings.

Do not print provider debug logs or raw API responses. The provider fetches the
full variable map even though state owns only selected non-secret values.

## Ownership and safety boundaries

- `terraform/bao` uses AWS without contacting Bao, so recovery infrastructure
  remains manageable while Bao is offline. `terraform/bao-config` requires
  the private Bao API. Keep these states separate.
- `terraform/ovh-vps` isolates the purchased server and OVH credentials from
  routine AWS and Bao administration.
- NixOS owns host networking, firewalls, containers, ACME, audit logging, and backups.
- Initialization, installation, OAuth enrollment, setup keys, and recovery material stay outside state.
- Cloudflare DNS-01 credential changes require separate review.
- `terraform/www.tf` forgets the retired provisioner without destroying or rebooting the droplet.
- No OIDC trust or orb-to-Bao connectivity is installed.

## Offline checks

Format and run the repository checks:

```sh
nix fmt
nix flake check
```

Treefmt checks Nix, Python, Terraform, Terragrunt, shell, JSON, and TOML. Linux
flake checks validate Terragrunt configuration and multi-unit execution, run
TFLint's recommended rules, validate provider schemas, and run native
mocked-provider tests. No cloud credentials or live backend are used.

Run only the Terraform checks on the current workstation:

```sh
nix build .#checks.x86_64-linux.terraform-lint .#checks.x86_64-linux.terraform --no-link
```

Provider downloads are pinned by the checked-in lock files and a cached Nix
mirror. The first build needs network access to fetch them; validation and tests
run in the sandbox without network access. After updating provider locks, update
the corresponding mirror hashes in `terraform/checks.nix` using Nix's reported
hash mismatch, then rerun the checks.

These checks do not prove that a live plan is safe. Review the live plan and
perform a post-apply access check from an authorized NetBird client.
