# CLIProxyAPI

- [Deployment profile](../../nixos/systems/chunkymonkey/cli-proxy-api.json): endpoints, SSH, state, Bao paths
- [NixOS module](../../nixos/modules/quadlets/cli-proxy-api/default.nix): service lifecycle
- The shell sets `CLI_PROXY_API_CONFIG`. Rotation and key-delivery commands accept `--config`.
- Management uses NetBird DNS and administrator membership. SSH uses Tailscale.

## Inference keys

1. Increment `cli_proxy_api_key_generation` in [cli-proxy-api.tf](../../terraform/bao-config/cli-proxy-api.tf).
2. [Plan and apply](../../terraform/README.md#plan-and-apply) `terraform/bao-config`.
3. Move consumers, then retire old keys separately. Preserve enrolled client keys.

On failure, retry the same generation. Delivery-only retry uses
`-replace=terraform_data.cli_proxy_api_deployment` when planning.
Finish pending rotations before endpoint changes. A new public endpoint needs a new generation.

Keep ephemeral reads and write-only fields to avoid secrets in state.
OIDC trust and orb connectivity are not installed.

## Manager Plus admin key

Deploy the current NixOS configuration before the first rotation:

```sh
export BAO_ADDR=https://bao.vpn.denys.me
unset BAO_TOKEN VAULT_TOKEN
bao login -no-print -method=userpass username=denys
cli-proxy-api-rotate-admin 1
```

- Start at 1. Retry the same generation after failure. Advance only for a new rotation.
- Keep `-no-print`. OpenBao CLI 2.5.4 lacks AWS login. Terraform still uses SSO.
- The old key expires before publication. Retry to publish the pending candidate.
- Leave pending Bao documents and bootstrap keys untouched.
- Avoid concurrent inference-key changes during the restart.

Admin rotation leaves service-management and inference keys unchanged.
Only the operator accesses both Bao and the host. Boot recovery uses local state.

## Restore

1. Stop `cli-proxy-api` and `cpa-manager-plus`. Block backups and admin maintenance.
2. Restore `/persist/dumps/cli-proxy-api.tar` from Restic.
3. Extract as `pod` into an empty `/persist/cli-proxy-api`, mode `0700`.
   Keep the database, keys, and rotation record together. Never overlay database or WAL files.
4. Start `cli-proxy-api`, then `cpa-manager-plus`.
5. Resume any unpublished rotation with its existing generation.

- Backups several admin generations behind Bao need reconciliation. Rotation cannot skip generations.
- Database rollback is not a rotation fix. It loses usage and configuration changes.
- OAuth and configuration files are live copies, not an atomic snapshot.
- Never run two instances against the same OAuth credentials.

## Access checks

- Public API: authenticated requests succeed, unauthenticated requests fail, management routes reject access.
- Public TLS: Cloudflare Full (strict).
- Private management: no public address records.
- `SSL_ERROR_BAD_CERT_DOMAIN`: check NetBird DNS. Exclude the private hostname from browser DNS-over-HTTPS and clear its DNS cache.
