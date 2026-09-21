# Workstation setup

## Requirements

Install Nix with flakes and `direnv`. Enter the pinned development shell before
running repository commands:

```sh
nix develop
```

No uv, Poetry, or separate Python environment is needed. The shell includes
pytest, Ruff, Terragrunt, OpenTofu (`tofu`), and the cloud CLIs.

## Local secret files

The following ignored files are 1Password Documents in the Private vault:

- `secrets/secrets.crypt.nix`
- `nixos/systems/cube/secrets.crypt.nix`

Download these Documents from 1Password to their listed paths after a fresh
clone. Keep their contents out of command output.

Copy `.env.example` to `.env` only when a Terraform operation requires its
variables. Keep `.env` mode 0600 and never commit or paste it into logs.

## OCI login

OCI credentials live under `~/.oci`. The provider uses the short-lived
security-token profile `meatcar`.

```sh
nix develop
oci session authenticate --profile-name meatcar --session-expiration-in-minutes 60
oci session validate --profile meatcar --auth security_token
```

Set `TF_VAR_oci_region` from that profile and set
`TF_VAR_oci_compartment_ocid` to the compartment containing `chunkymonkey`.

## Terraform state bootstrap

All roots use encrypted, locked state in `terraform-state-denys-me`. The main
root owns the backend resources through `module.state`; do not apply
`tf-modules/terraform-state` independently against the existing account.
Bootstrapping a new account requires a separate state-bootstrap procedure.

## DigitalOcean image

```sh
nix build .#doImage
```

The image archive is linked at `result`.
