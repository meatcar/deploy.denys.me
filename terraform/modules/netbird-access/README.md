# Private access cutover

`private_server_ips` holds verified NetBird addresses keyed by host; only `vps`
is allowed. An empty map creates no destination groups, server policies or
split DNS. Never substitute Bao, Chunkymonkey, a public IP or an invented peer ID.

Before deployment:

1. Confirm administrator SSH over the existing Tailscale targets. Keep that
   route until NetBird SSH and recovery have been tested. Bao's public recovery
   SSH is unchanged. VPS public SSH and Mosh are closed by this change.
2. Enroll the VPS through the existing NetBird client. Read back its overlay
   IPv4 address and identity, then supply it as `private_server_ips.vps`. The
   provider resolves the address to exactly one enrolled peer.
3. Supply the complete `private_access_peer_ids.administrators` membership.
   Administrators get host management and SSH/Mosh. Do not enable the default
   allow-all policy or broad overlapping policies.
4. Review a normal OpenTofu plan before an approved apply, then deploy through
   the existing recovery path. Client devices must accept NetBird DNS. Host
   clients intentionally retain `DisableDNS = true`.

`znc.denys.me` uses split DNS. Billing/TRMNL/SilverBullet use
`billing.vpn.denys.me`, `trmnl.vpn.denys.me` and `txt.vpn.denys.me` under the
existing CPA administrator policy. DNS does not authorize traffic: private HTTPS
is redirected from NetBird 443 to 9443, and raw ingress guards reject other
interfaces before VPN-managed accepts.

After deployment, test an allowed and denied peer, the VPS website/Mumble, and
public SNI with a private HTTP Host. Run `private-access-isolation` on a
KVM-capable builder before deployment.

## Orb plan access

`amp--orbs` holds Amp orb peers of every project that needs Bao. Network access
is shared; each project's Bao JWT role limits what it can read.
Its only policy grants one-way TCP/443 to `bao-server`. Only the Bao DNS zone
adds this group, so orbs can resolve `bao.vpn.denys.me` for TLS. Setup-key
enrollment owns its peer membership; Terraform does not reconcile that list.

After reviewing and applying this module, review every live policy and route
that includes the orb group or `All`. NetBird policies only grant access; this
narrow rule cannot override broader grants. The default `All` to `All` policy
must not remain enabled. Preserve legitimate device access with explicit groups
before narrowing broad policies. Do not grant orbs SSH, routed networks, other
groups, or inbound access. Keep `bao-server` exclusive to Bao.

### Create the project enrollment key

Create the key outside Terraform. `netbird_setup_key` puts its plaintext in
state, which plan agents can read.

In [Settings > Setup Keys](https://app.netbird.io/settings?tab=setup-keys):

1. Create a **Reusable** key with **Ephemeral peers** enabled.
2. Auto-assign **only** `amp--orbs`.
3. Set unlimited usage and a long expiration. Each orb start and resume enrolls
   a new peer, so usage limits run out fast. Expiry and revocation do not evict
   enrolled peers; on compromise, also disable the orb policy.
4. Disable **Extra DNS labels**.

Store it as the Amp project secret `NETBIRD_SETUP_KEY` in each project that
needs Bao, not a personal secret, which reaches every orb. Use hidden input, not
in shell history, command arguments, tracked files, or Terraform variables:

```bash
(
  set +x
  read -rsp 'NetBird setup key: ' key; printf '\n'
  printf '%s' "$key" | amp secrets set NETBIRD_SETUP_KEY \
    --project meatcar/deploy.denys.me --secret --data-file -
)
```

Anyone holding this reusable key can enroll until expiration or revocation. It does not prove Amp identity. Bao authentication remains a
separate requirement. Revoking or expiring the key does not disconnect enrolled
peers; disable the orb policy or remove those peers to revoke current access.
Ephemeral peers are normally removed after more than ten minutes offline.
See [setup-key behavior](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys).

After orb enrollment is configured, test both a fresh and resumed orb. Confirm
ephemeral status and membership in only this project group, with no extra DNS
labels. Verify `bao.vpn.denys.me` resolves and HTTPS validates its certificate.
Check that Bao SSH and other ports, CPA, VPS, other peers, and inbound
connections are denied. Test that an expired/revoked key fails fresh enrollment;
delete test peers separately. Mocked tests verify only this module's declared
rules, not live overlapping policies, routes, membership, DNS, or connectivity.
