# Private access cutover

Cube and VPS have no enrolled NetBird peers yet. `private_server_ips = {}`
creates no destination groups, server policies or split DNS. Never substitute
Bao, Chunkymonkey, a public IP or an invented peer ID.

Before deployment:

1. Confirm administrator SSH over the existing Tailscale targets. Keep that
   route until NetBird SSH and recovery have been tested. Bao's public recovery
   SSH is unchanged. Cube/VPS public SSH and Mosh are closed by this change.
2. Enroll Cube/VPS through the existing NetBird client. Read back each overlay
   IPv4 address and identity, then supply `private_server_ips` keyed by `cube`
   and `vps`. The provider resolves each address to exactly one enrolled peer.
3. Supply complete `private_access_peer_ids` memberships. Administrators get
   host management and SSH/Mosh; household peers get Cube HTTPS; storage peers
   get Cube SMB only. Household/storage default empty. Membership is not
   additive and roles do not imply each other. Do not enable the default
   allow-all policy or broad overlapping policies.
4. Select trusted Cube LAN interfaces explicitly in
   `mine.privateAccess.trustedLANInterfaces`. The empty default closes LAN SMB
   and disables WSD. Do not infer trust from DHCP or private address ranges.
   Provision Samba passwords interactively with `smbpasswd -a` for selected
   Unix members of `storage`. Anonymous shares no longer work.
5. Review a normal OpenTofu plan before an approved apply, then deploy through
   the existing recovery path. Client devices must accept NetBird DNS. Host
   clients intentionally retain `DisableDNS = true`.

Existing private Cube names and `znc.denys.me` use split DNS. The Cube zone
keeps Plex/Ombi as CNAMEs to the public VPS hostname `denys.me`, including for
storage-only peers. Billing/TRMNL use `billing.vpn.denys.me` and
`trmnl.vpn.denys.me` under the existing CPA administrator policy. DNS does not
authorize traffic: private HTTPS is redirected from NetBird 443 to 9443,
and raw ingress guards reject other interfaces before VPN-managed accepts.
Public HTTP challenge forwarding remains for existing certificate renewal.

After deployment, test an allowed and denied peer for each role, both public
Plex/Ombi URLs, VPS website/Mumble, certificate renewal, SMB anonymous denial,
and public SNI with a private HTTP Host. Confirm the media integrations still
use reachable container endpoints after removing host networking. Never
configure Plex network-based authentication bypass for the proxy network.
Run `private-access-isolation` on a KVM-capable builder before deployment.

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
Check that Bao SSH and other ports, CPA, Cube, VPS, other peers, and inbound
connections are denied. Test that an expired/revoked key fails fresh enrollment;
delete test peers separately. Mocked tests verify only this module's declared
rules, not live overlapping policies, routes, membership, DNS, or connectivity.
