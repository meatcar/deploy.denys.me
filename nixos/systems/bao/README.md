# OpenBao

- [configuration.nix](configuration.nix): service, TLS, audit, backups
- [vps.nix](vps.nix): hardware, network, disks
- [Terraform](../../../terraform/README.md): infrastructure and API configuration
- Access: `https://bao.vpn.denys.me` through NetBird

Reenrollment with a new VPN address requires listener and DNS updates.
Keep the listener pinned to a private address. Never publish public A/AAAA records for Bao.

## Install

**Erases the VPS disk. Requires explicit approval.**

1. Use `baoInstaller` and `baoVps` from [flake-parts](../../../flake-parts/). Test in a VM first.
2. Set `NIXOS_ANYWHERE_KNOWN_HOSTS` to `output/ovh-bao-vps/bao-known_hosts`.
3. Select `$HOME/.1password/agent.sock` explicitly. Preserve host keys with `--copy-host-keys`.
4. After reboot, verify the host-key pin, root login, and networking before bootstrap.

The installer enforces host-key checking. It does not provision AWS or initialize Bao.
Never rerun initialization on the existing database.

## Recover

In the 1Password Private vault:

| Item | Contents |
| --- | --- |
| `OpenBao administrator` | Userpass login |
| `OpenBao recovery material` | Recovery shares, Restic password |
| `OpenBao VPS runtime credentials` | Separate KMS and backup IAM credentials |
| `OpenBao DNS renewal token` | Scoped DNS-01 credentials |

- Create runtime IAM credentials outside Terraform. Keep recovery material independent of this host.
- Preserve KMS and backup-bucket destruction protection. Recovery shares cannot replace a lost KMS key.
- After a backup outage longer than 72 hours, replace the backup token.
- Test a Raft restore in an isolated, loopback-only Bao instance with KMS access. Verify unseal and admin login.
- Keep the repository's broader Cloudflare token off this host.
