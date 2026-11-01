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

## VPS

`private_server_ips` holds verified NetBird addresses keyed by host; only `vps`
is allowed. An empty map creates no server group, policies or split DNS. Never
substitute Bao, Chunkymonkey, a public IP or an invented peer ID.
`znc.denys.me` uses split DNS. Host clients keep `DisableDNS = true`.

DNS does not authorize traffic: private HTTPS is redirected from NetBird 443 to
9443, and raw ingress guards reject other interfaces before VPN-managed accepts.
Run `private-access-isolation` on a KVM-capable builder before deployment.

## Agent VM plan access

`role-agent-vms` holds agent VM peers (today: Amp orbs) of every project that
needs Bao. Network access
is shared; each project's Bao JWT role limits what it can read.
Its only policy grants one-way TCP/443 to `server-bao`. Only the Bao DNS zone
adds this group, so orbs can resolve `bao.vpn.denys.me` for TLS. Setup-key
enrollment owns its peer membership; Terraform does not reconcile that list.

After reviewing and applying this module, review every live policy and route
that includes `role-agent-vms` or `All`. NetBird policies only grant access; this
narrow rule cannot override broader grants. The default `All` to `All` policy
must not remain enabled. Preserve legitimate device access with explicit groups
before narrowing broad policies. Do not grant agent VMs SSH, routed networks, other
groups, or inbound access. Keep `server-bao` exclusive to Bao.

### Enrollment key

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

2. `tofu state rm module.netbird_access.netbird_setup_key.agent_vms`, add an
   `import` block for the printed ID in `terraform/imports.tf`, update the
   resource, and apply. Delete the block after apply.
3. Revoke the old key: `PUT /api/setup-keys/<old id>` with `revoked: true`.

Anyone holding this reusable key can enroll until expiration or revocation. It does not prove Amp identity. Bao authentication remains a
separate requirement. Revoking or expiring the key does not disconnect enrolled
peers; disable `agent-vms-bao` or remove those peers to revoke current access.
Ephemeral peers are normally removed after more than ten minutes offline.
See [setup-key behavior](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys).

After orb enrollment is configured, test both a fresh and resumed orb. Confirm
ephemeral status and membership in only this project group, with no extra DNS
labels. Verify `bao.vpn.denys.me` resolves and HTTPS validates its certificate.
Check that Bao SSH and other ports, CPA, VPS, other peers, and inbound
connections are denied. Test that an expired/revoked key fails fresh enrollment;
delete test peers separately. Mocked tests verify only this module's declared
rules, not live overlapping policies, routes, membership, DNS, or connectivity.
