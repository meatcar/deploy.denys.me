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
