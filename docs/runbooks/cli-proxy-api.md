# CLIProxyAPI operations

CLIProxyAPI runs on `chunkymonkey`. The public inference endpoint is
`https://cpa.pvlv.ca/v1`. Manager Plus is private at
`https://cpa.vpn.denys.me`; clients must use NetBird DNS and belong to the
approved administrator group. SSH remains on Tailscale.

Runtime state and OAuth credentials live under `/persist/cli-proxy-api` and are
backed up as `/persist/dumps/cli-proxy-api.tar`. Do not run two instances against
the same OAuth credentials. The rootless service exposes no backend port or
container socket.

## Backup and restore

Restic waits for the `pod` user service `cli-proxy-api-backup` before each backup.
It archives an online SQLite snapshot with the manager keys and rotation record
under the admin-maintenance locks. Preparation failure aborts the Restic run
and preserves the previous archive. OAuth files and application configuration
are live copies, not a cross-file transaction.

To restore, stop `cli-proxy-api` and `cpa-manager-plus`, and prevent backup and
admin-maintenance commands from running. Restore the archive from Restic and
extract it as `pod` into an empty `/persist/cli-proxy-api` directory with mode
`0700`. Do not overlay an existing database or its WAL files. Start
`cli-proxy-api`, then `cpa-manager-plus`; the recovery hook reapplies the saved
admin rotation locally without Bao. Retry an unpublished rotation with its
existing generation before starting another.

## Deployment settings

Edit [`nixos/systems/chunkymonkey/cli-proxy-api.json`](../../nixos/systems/chunkymonkey/cli-proxy-api.json)
for hostnames, SSH, state location, and Bao paths. NixOS, Terraform, and operator
commands read this non-secret profile. Keep credentials out of it.

The development shell selects this profile through `CLI_PROXY_API_CONFIG`. Both
`cli-proxy-api-rotate-admin` and `cli-proxy-api-deploy-key` accept
`--config /path/to/deployment.json` to select another deployment.

Finish pending rotations before changing endpoints. A public endpoint change
requires a new `cli_proxy_api_key_generation` to update published connection details.

Initial application settings live in
[`settings.nix`](../../nixos/modules/quadlets/cli-proxy-api/settings.nix).
Initialization preserves existing configuration and credentials.

## Project inference key

Terraform owns inference-key staging, delivery, verification, and publication
at `kv/github/meatcar/deploy.denys.me/dev/cli-proxy-api`. Use the
[infrastructure workflow](terraform.md) with `terraform/bao-config`.

Increment `cli_proxy_api_key_generation` only for a deliberate rotation. Retry
the current plan to reuse a staged key after failure. To retry delivery alone,
plan with `-replace=terraform_data.cli_proxy_api_deployment`. Existing inference
keys remain valid until consumers move and an operator retires them separately.

Never replace ephemeral reads or `data_json_wo` writes with stateful password
resources or ordinary secret data sources. Do not enable Terraform debug or
trace logging. No OIDC trust or orb connectivity exists, so orbs cannot yet
read the published secret.

## Manager Plus admin key

Deploy the current NixOS configuration before the first rotation. Terraform
owns only the exact-path read policy. The operator stages and publishes the
credential through Bao and delivers it over host-key-checked SSH.

```sh
export BAO_ADDR=https://bao.vpn.denys.me
unset BAO_TOKEN VAULT_TOKEN
bao login -no-print -method=userpass username=denys
cli-proxy-api-rotate-admin 1
```

OpenBao CLI 2.5.4 has no AWS login and userpass requires `-no-print`. Terraform
continues to authenticate with AWS SSO.

The generation starts at 1. After any failure, retry the same generation. Use a
new number only for an intentional new rotation. Do not edit or delete pending
Bao documents by hand. Avoid concurrent inference-key changes during the brief
Manager Plus restart.

The old admin key stops working immediately after the local reset, including
the bootstrap copy in 1Password. Publication happens afterward, so consumers
may briefly have neither a working old key nor a published new key. If
publication fails, retry the same generation; the active candidate remains in
the pending Bao document.

The host records delivery in `/persist/cli-proxy-api` and systemd reapplies that
key locally before Manager Plus starts. Boot and recovery do not contact Bao.
Restore the manager data and rotation record together. Do not edit the
bootstrap key file and do not roll back the whole database, which would discard
usage and configuration changes.

The rationale and credential boundaries are recorded in
[the CLIProxyAPI design note](../design/cli-proxy-api.md).

## Network checks

Public authenticated inference requests should succeed, unauthenticated ones
should return 401, and management routes should return 404. Manager Plus should
be reachable only through NetBird. Keep Cloudflare Full (strict) mode for
`cpa.pvlv.ca`.

If Firefox reports `SSL_ERROR_BAD_CERT_DOMAIN`, verify that
`cpa.vpn.denys.me` resolves through NetBird DNS. DNS-over-HTTPS can bypass the
system resolver; exclude this hostname and clear the browser DNS cache. Do not
publish a public address record for the private hostname.
