# cube.denys.me

- [Host configuration](configuration.nix)
- [Disks, encryption, and filesystems](hardware-configuration.nix)
- [Services](modules/)
- [Workstation setup](../../../README.md#setup)

Use the declared disk IDs and current filesystem configuration for recovery.
Disk replacement and installation require explicit approval.

## Container VPN

Transmission and Jackett share Gluetun's network namespace. NetBird and
Tailscale remain host-only. Nginx reaches the applications on loopback ports.

Download a WireGuard configuration with a numeric endpoint IP. Keep
the plaintext outside this repository and out of chat. From the repository
root, import it using the existing agenix recipient policy:

```sh
direnv exec . sh -c 'cd secrets && agenix -e wg-config.age' < /absolute/path/to/wg.conf
jj status
```

Non-interactive stdin tells agenix to import the file without opening an
editor or printing its contents. Only `secrets/wg-config.age` is stored
in the repository, encrypted to your key and Cube's host key. `jj status`
includes that new ciphertext in the Git-backed flake. Later edits may require
your decryption identity through agenix's `-i` option.

Cube refuses to build without that encrypted file. On deployment, agenix
decrypts it to `/run/agenix/wgConfig`, owned by root with mode `0400`.
Gluetun mounts that file read-only; plaintext never enters the Nix store.
Changing the encrypted file triggers a Gluetun restart on activation so Docker
remounts the new secret. Both applications restart with it and wait for VPN
health. Gluetun's firewall blocks direct fallback while the tunnel reconnects.
VPN port forwarding is not configured.

After deployment, verify both web interfaces through nginx, confirm the public
IP and DNS from each application container, and test that outbound traffic
fails while the VPN endpoint is unreachable. Restore connectivity and check
recovery. Restart Gluetun separately to check that both applications reattach.
Do not remove `/persist/wireguard` until the migration is verified.
