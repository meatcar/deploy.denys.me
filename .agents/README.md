# deploy.denys.me orbs

Uses the [orb access template](../templates/orb-access/.agents/README.md) through
local symlinks. [Taskfile.yml](Taskfile.yml) selects the `prod/plan` Bao role and
caches main-root providers at setup without backend access. Resume only restores
network access.

`task --taskfile .agents/Taskfile.yml doctl -- compute droplet list` runs doctl
with the read-only DigitalOcean token: Droplets, images, snapshots, regions,
sizes and actions only.

## Agent plans

```sh
direnv exec . task --taskfile .agents/Taskfile.yml plan
```

The task logs into Bao, mints a project-scoped AWS web identity for the
`tofu-plan` role, and reads these KV v2 documents from mount
`projects/meatcar/deploy.denys.me`. A missing document or field, or an extra
field, stops the task before init.

| Document | Fields |
| --- | --- |
| `prod/plan/digitalocean` | `TF_VAR_digitalocean_token` |
| `prod/plan/ovh` | `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` |

It plans only targets whose provider has a read-only credential that cannot read
secrets:

```sh
tofu -chdir=terraform plan -input=false -lock=false \
  -target=module.state -target=module.bao_support -target=module.aws_plan_access \
  -target=digitalocean_droplet.www -target=ovh_vps.bao
```

Cloudflare, NetBird, OCI and Railway read access exposes object contents, SQL,
logs, instance metadata or owner authority, so they stay out. Add a target only
with a verified read-only credential for its provider.

- The task passes only declared non-secret root inputs and proxy/CA settings.
  It never uses operator credentials or writes a saved plan.
- Tokens and provider values stay in memory. The AWS token and isolated HOME are
  temporary files, removed on exit. Do not snapshot a running plan.
- Run only the main root. `terraform/bao-config` plans read CLIProxyAPI secrets.
- The output is a preview. Treat anything an agent reads as disclosed. Targets
  are not a security boundary; provider permissions and Bao policies are. An
  operator applies only from a fresh, unrestricted plan.

Revoke agent access at once (applying both roots restores it):

```sh
bao delete auth/amp/role/project--meatcar--deploy.denys.me--prod--plan--read
aws iam delete-role-policy --role-name tofu-plan --policy-name main-root-refresh
```

Also revoke the NetBird setup key, see
[key rotation](../terraform/modules/netbird-access/README.md#enrollment-key).
Amp-side identity revocation can lag up to 24 hours.
