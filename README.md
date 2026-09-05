# Infrastructure for denys.me

[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

NixOS, OpenTofu, and service configuration for denys.me.

## Start here

- [Set up a workstation](docs/runbooks/workstation-setup.md)
- [Plan and apply Terraform](docs/runbooks/terraform.md)
- [Operate CLIProxyAPI](docs/runbooks/cli-proxy-api.md)
- [Install and recover the OpenBao host](nixos/systems/bao/README.md)
- [Operate Paseo Relay](railway/paseo-relay/README.md)

Run repository tools through `nix develop`. The dev shell pins OpenTofu, cloud
CLIs, pytest, Ruff, and the other supported tools.

## Repository map

- `nixos/`: host and service configuration
- `terraform/`: infrastructure split into independent state roots
- `packages/cli-proxy-api/`: CLIProxyAPI administration commands and tests
- `packer/`, `flyio/`, `railway/`: platform-specific configuration
- `docs/runbooks/`: operator procedures
- `docs/design/`: durable design decisions

Tailscale remains in service alongside hosted NetBird. The self-hosted VPN
configuration is historical, not an active deployment path.
