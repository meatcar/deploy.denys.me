# Plan and apply infrastructure

Use the [workstation environment](workstation-setup.md). From the repository
root, select a [state root](../../terraform/README.md), then save and review its
plan before applying that same file. This example selects NetBird:

```sh
terragrunt --working-dir terraform/netbird run -- plan -out=change.tfplan
terragrunt --working-dir terraform/netbird run -- show change.tfplan
terragrunt --working-dir terraform/netbird run -- apply change.tfplan
```

Terragrunt initializes OpenTofu and the existing S3 backend automatically.
Plans contain secrets; keep them private and ignored. Re-plan dependent units
after upstream changes. Separate states have no shared transaction or rollback.
Bulk apply approves individual units automatically.

Terragrunt manages provider resources, not NixOS activation. Host activation
is configured in the `deploy` output of [flake.nix](../../flake.nix). Host
installation, OAuth enrollment, and recovery are separate operator procedures.

## Access

Credentials come from the ignored `.env`; required names are in
[.env.example](../../.env.example). Never put secrets in HCL, tfvars, shell
history, logs, or provider debug output.

- AWS state and Bao provider access use the current SSO profile. Renew it with
  `aws sso login --profile "$AWS_PROFILE"`.
- OCI uses the short-lived session described in [workstation setup](workstation-setup.md#oci).
- NetBird uses `NB_PAT`; Bao access requires NetBird connectivity.
- Railway uses `RAILWAY_TOKEN`. Its provider fetches the full variable map;
  Terraform owns only the explicitly selected non-secret values.
- OVH uses `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, and `OVH_CONSUMER_KEY`.

## Review boundaries

### NetBird

Peer IDs and complete group memberships are in
[`terraform/netbird/terragrunt.hcl`](../../terraform/netbird/terragrunt.hcl).
Verify these against the hosted account; peer names are not identities.
Keep `bao-server` limited to the Bao peer and preserve approved admin members.
Account-wide policies can bypass narrower policies; `prevent_destroy` does not
prevent in-place membership or policy changes.

CPA requires TCP 443 and 9443 because NetBird filters both sides of the host
redirect. It grants no SSH. Private DNS must resolve through NetBird without an
overlapping `vpn.denys.me` zone. Preserve Tailscale alongside NetBird. After an
access change, verify private DNS, TLS, and authentication from the affected client.

### OpenBao and OVH

Keep AWS recovery infrastructure in `bao` independent of the private API in
`bao-config`. Preserve the exact trusted AWS SSO role and userpass recovery
account. Never reinitialize the existing Bao database or auth setup.
Runtime IAM credentials, recovery shares, backup passwords, and application
passwords remain outside Terraform.

The purchased VPS root must retain `plan = []`. Purchase, image, SSH-key, or
plan-option changes can reinstall the server or alter its service. Scope OVH
access to `GET /auth/details` and `GET /vps/vps-5c07e980.vps.ovh.ca` where possible.
NixOS owns the OS and SSH keys. See [OpenBao operations](openbao.md) for recovery.

### Railway

The root owns Paseo, RSSHub, and monitoring resources listed in
[`applications.tf`](../../terraform/railway/applications.tf) and
[`main.tf`](../../terraform/railway/main.tf). IDs are in `terragrunt.hcl`.
Adoption plans must contain imports only, with no creates, updates, or deletes.

Service and variable updates redeploy workloads. Removing a nested `volume`
deletes its data even with service-level `prevent_destroy`.

RSSHub's source connection stays Railway-managed because the provider cannot
read its branch trigger. Secret variables, computed regions/replicas, volume
sizes, and unsupported service settings also remain Railway-managed unless
explicitly declared. See [Paseo operations](paseo-relay.md) for its settings.

### Other boundaries

- Review Cloudflare DNS-01 credential changes separately.
- `terraform/www.tf` forgets a retired provisioner without destroying or rebooting its droplet.
- No OIDC trust or orb-to-Bao connectivity is installed.

## Maintaining checks

Use the [repository quality check](../../README.md#workflow). Its implementation
is in `flake.nix`, `treefmt.nix`, and `terraform/checks.nix`. Provider validation
and native tests use mocked providers and a pinned mirror, without live backends.
After updating provider locks, update the mirror hashes from Nix's reported
hash mismatch. The first fetch requires network access; checks run sandboxed.
Passing checks does not establish that a live plan is safe.
