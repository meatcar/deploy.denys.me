# NetBird access

Terraform owns the whole NetBird account: settings, users, server peers, groups,
policies, DNS and the agent VM setup key. Do not change it in the dashboard.

Groups:

- `role-*`: who. Users get roles through `auto_groups`; propagation adds all
  their peers. Peers without a user join through a setup key's `auto_groups`.
- `server-*`: what. Terraform pins each to one peer.

Policies grant a `role-*` group ports on a `server-*` group. DNS zones go to the
same groups. The `Default` all-to-all policy stays disabled.

| Role | Gets |
| --- | --- |
| `role-admins` | Bao 443, Chunkymonkey 443/9443 (CPA, billing, TRMNL, txt), VPS SSH/Mosh/443/IRC |
| `role-agent-vms` | Bao 443 only |

Servers enroll with a setup key, never a user login: a user's roles would
propagate to the server.

## Sharing access

1. Add a `netbird_user` with their `email`, `role = "user"` and the `role-*`
   groups in `auto_groups` to `account.tf`. Apply sends the invite.
2. They log in on each device. Propagation adds every device to their roles.

Revoke: remove the group from `auto_groups`, or remove the user. New kind of
access: add a `role-*` group with `ignore_changes = [peers]` and a policy. Do not
widen `role-admins`.

## Agent VMs

`role-agent-vms` holds agent VM peers (Amp orbs) of every project that needs
Bao. Its only policy, `agent-vms-bao`, grants TCP/443 to `server-bao`; each
project's Bao JWT role limits reads. Only the Bao DNS zone includes it. The
setup key owns its membership.

NetBird policies only grant. Keep `Default` disabled and keep `server-bao`
exclusive to Bao.

## Enrollment key

`netbird_setup_key.agent_vms` is imported, never created: create or replace
writes the plaintext key to state, which plan agents can read. Any change that
forces replacement (`name`, `type`, `ephemeral`, `usage_limit`) must instead
rotate:

1. Create the key through the API and pipe it straight into the Amp project
   secret `NETBIRD_SETUP_KEY` (not a personal secret, which reaches every orb):

   ```bash
   curl -fsS -H "Authorization: Token $NB_PAT" -H 'Content-Type: application/json' \
     https://api.netbird.io/api/setup-keys -d "$(jq -n --arg g <role-agent-vms id> \
       '{name:"<name>",type:"reusable",ephemeral:true,usage_limit:0,expires_in:0,
         auto_groups:[$g],allow_extra_dns_labels:false}')" |
     tee >(jq -r .id >&2) | jq -j .key |
     amp secrets set NETBIRD_SETUP_KEY --project meatcar/deploy.denys.me --secret --data-file -
   ```

2. `tofu state rm module.netbird_access.netbird_setup_key.agent_vms`, add a
   temporary `import` block for the printed ID in `terraform/`, update the
   resource, and apply. Delete the block after apply. `nix flake check` fails
   while the block exists.
3. Revoke the old key: `PUT /api/setup-keys/<old id>` with `revoked: true`.

Anyone holding the key can enroll until it expires or is revoked; Bao login is
a separate check. Revoking the key does not evict enrolled peers: disable
`agent-vms-bao` or delete the peers. See
[setup keys](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys).
