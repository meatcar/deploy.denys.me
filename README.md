# deploy.denys.me

Personal infrastructure: NixOS hosts deployed with
[deploy-rs](https://github.com/serokell/deploy-rs), and OpenTofu for cloud,
DNS, NetBird and OpenBao.

| Host | Platform | Runs |
| --- | --- | --- |
| `chunkymonkey` | OCI, aarch64 | Traefik and rootless Podman quadlets: Invoice Ninja, LaraPaper, SilverBullet, CLIProxyAPI |
| `vps` (hostname `to`) | DigitalOcean | nginx for denys.me, ZNC, Mumble |
| `bao` | OVH | OpenBao, reachable only over NetBird |

## Layout

```
flake.nix             inputs and entry point
flake-parts/          devshell, checks, formatting, packages, hosts, deploy
nixos/modules/        reusable NixOS services
nixos/systems/        per-host configuration and recovery runbooks
packages/             deps (update tool), cli-proxy-api (key operations), doctl
terraform/            main OpenTofu root; modules/ are child modules, not states
terraform/bao-config/ OpenBao auth, policies and project mounts (second root)
secrets/              agenix-encrypted host secrets
templates/orb-access/ flake template: NetBird and Bao access for Amp orbs
.agents/              this repository's orb setup and agent plan task
tests/                tests for the exported template
```

## Use

1. Install Nix with flakes and direnv, then review and allow `.envrc`.
2. For infrastructure access, copy `.env.example` to `.env` with mode `0600`.
   See [access](terraform/README.md#access).

```sh
gitleaks git --redact                # scan untrusted changes before loading Nix
nix flake check                      # tests, lints, formatting
deploy .#<host>                      # build and activate a host
```

Infrastructure: [plan and apply](terraform/README.md#plan-and-apply).

## Dependencies

[Renovate](renovate.json) tracks every pinned version. The same lookup runs
locally:

```sh
task deps -- list                 # detected versions
task deps -- outdated             # available updates
task deps -- upgrade [--major] [flake|opentofu|images|sources|actions|other]
task deps -- lint                 # pins Renovate cannot see; also a flake check
```

Pin new images as literal `name:tag@digest` strings, and annotate other
versions with `# renovate: datasource=… depName=…`. Add hash-bearing sources to
`legacyPackages.sources`.

## Runbooks

- [OpenBao](nixos/systems/bao/README.md): installation and recovery
- [CLIProxyAPI](packages/cli-proxy-api/README.md): keys and restore
- [NetBird](terraform/modules/netbird-access/README.md): groups, sharing access, key rotation
- [SilverBullet](nixos/modules/quadlets/silverbullet/README.md): first deploy and limits
- [Amp orbs](.agents/README.md): orb lifecycle and agent plans
