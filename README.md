# Infrastructure for denys.me

NixOS, OpenTofu, and service configuration for denys.me.

## Workflow

Direnv loads the pinned environment and optional local credentials.

```sh
nix flake check
```

Plan and apply through [Terragrunt](docs/runbooks/terraform.md).

## Reference

- [Set up a workstation](docs/runbooks/workstation-setup.md)
- [Operate CLIProxyAPI](docs/runbooks/cli-proxy-api.md)
- [Operate OpenBao](docs/runbooks/openbao.md)
- [Operate Paseo Relay](docs/runbooks/paseo-relay.md)

## Repository map

- [nixos/](nixos/): hosts and services
- [terraform/](terraform/): independent infrastructure state roots
- [packages/](packages/): operations and tests
- [docs/runbooks/](docs/runbooks/): procedures
- [docs/design/](docs/design/): design decisions
