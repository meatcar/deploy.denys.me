# Infrastructure for denys.me

NixOS hosts and Terragrunt-managed infrastructure.

## Setup

1. Install Nix with flakes and direnv. Review and approve `.envrc`.
2. For infrastructure access, copy `.env.example` to `.env` with mode `0600`.
   See [credentials](terraform/README.md#access).
3. Download these 1Password Documents from the Private vault to their ignored paths:
   - `secrets/secrets.crypt.nix`
   - `nixos/systems/cube/secrets.crypt.nix`

## Workflow

Scan untrusted changes with standalone Gitleaks before loading the Nix environment.
The `secret-scan` flake check runs after Nix copies tracked files into its store.

```sh
nix flake check
```

[Plan and apply with Terragrunt](terraform/README.md#plan-and-apply).

## Where to look

- [flake-parts/](flake-parts/): tools, checks, and flake outputs
- [nixos/](nixos/): hosts and services
- [terraform/](terraform/): infrastructure and provider constraints
- [CLIProxyAPI](packages/cli-proxy-api/README.md): keys and recovery
- [OpenBao](nixos/systems/bao/README.md): installation and recovery
- [Paseo](nixos/modules/quadlets/paseo-relay/README.md): relay deployment and clients
