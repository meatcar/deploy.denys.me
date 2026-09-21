# OpenBao operations

OpenBao runs on the OVH VPS. Infrastructure changes use the
[Terraform runbook](terraform.md). Do not rerun initialization on this server.

## Access

- `app.netbird.io` manages the VPN. No self-hosted VPN server is required.
- `https://bao.vpn.denys.me` is the private OpenBao endpoint. HTTP is not served.
- `bao-admins` can initiate TCP 443 connections to `bao-server`.
- Public IPv4 and IPv6 traffic to ports 443, 8200, and 8201 is dropped before
  NetBird's dynamic firewall rules. OpenBao also binds only to `wt0`.
- `*.x.denys.me` is reserved for future public services, not OpenBao.
- SSH uses the personal `me@onepassword` Ed25519 key through the 1Password
  agent. The private key remains in 1Password.

The server belongs to `bao-server` at `10.201.219.143`. Before changing client
access, verify its peer ID and the complete `bao-admins` membership. Test private
DNS, TLS, and authenticated access from that client afterward.

## Server and installation

Service `vps-5c07e980.vps.ovh.ca`, IPv4 `51.222.84.199`, uses BIOS boot and a
40 GB `/dev/sda`. `nixos/systems/bao/vps.nix` records its MAC address, DHCPv4 configuration
and static IPv6 gateway. It is specific to this server.
It pins the API listener to the assigned NetBird address. If the server is
reenrolled with another VPN address, update this setting and private DNS.
Dynamic interface lookup can return an empty address during startup, causing
a wildcard listener; the pinned address instead fails closed and retries.

The local connection details and public-key pin are in `output/ovh-bao-vps`.
SSH clients must explicitly select `$HOME/.1password/agent.sock`.
`ssh-add` otherwise uses a different agent on the administration workstation.

`baoInstaller` pins nixos-anywhere through nixpkgs and patches its SSH defaults
to enforce host-key checking. Stock version 1.13.0 disables checking before
processing command-line SSH options. `NIXOS_ANYWHERE_KNOWN_HOSTS` selects the
verified pin file. Preserve host keys through installation with
`--copy-host-keys`; no private SSH key needs to be exported from 1Password.

**Installation erases the VPS disk and requires explicit disk-replacement
approval.** Use the `baoInstaller` package and `baoVps` configuration in
`flake.nix`; test the installer in a VM before replacing a server. Select the
verified `output/ovh-bao-vps/bao-known_hosts` pin and the 1Password agent
explicitly. Installation does not create AWS resources or initialize Bao.

The installer uses a temporary authentication key during conversion. The final
NixOS root account authorizes only the declared 1Password key. After reboot,
verify the pinned host key, 1Password root login and networking before bootstrap.

## Automatic unseal and backups

`terraform/bao` provisions an AWS KMS key and one S3 Restic repository in
`ca-central-1`. Its separate state key is `bao/state`. It does not provision
compute, DNS, a NetBird server or IAM access keys.

Use the [infrastructure workflow](terraform.md) with `terraform/bao`. Create the scoped
runtime credentials outside Terraform, consume them without printing them, and
store recovery material and backup passwords in 1Password. KMS availability is
required for automatic unseal after a reboot; recovery shares do not replace a
lost KMS key. Destruction protection is enabled for the key and bucket.

The daily backup starts between 03:00 and 03:30 America/Toronto. It renews a
72-hour periodic token and exports a Raft snapshot before uploading to Restic.
An outage longer than the token period requires a replacement backup token.
Retention is 7 daily, 5 weekly and 12 monthly snapshots.

Verify recovery by restoring a Raft snapshot into a separate, loopback-only
OpenBao instance with access to KMS. Confirm automatic unseal and administrator
authentication before removing the isolated test instance.

The Private vault in 1Password contains:

- `OpenBao administrator`, username `denys` and its password.
- `OpenBao recovery material`, three recovery shares and the Restic password.
- `OpenBao VPS runtime credentials`, separate KMS and backup IAM credentials.
- `OpenBao DNS renewal token`, scoped to `denys.me` for ACME DNS-01.

Do not publish an A or AAAA record pointing OpenBao at the public server address.
The broader repository Cloudflare token must not be installed on the server.
