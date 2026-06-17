# Infrastructure for denys.me

[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

## Requirements

- `direnv`
- `nix` or `nixos`

All OCI and Terraform commands should be run inside the Nix dev shell so the
repo-provided OpenTofu and OCI CLI versions are used:

```sh
nix develop
oci --version
```

If `nix` is not available, you can try to make do with:

- `terraform` with [terraform-provider-secret](https://github.com/tweag/terraform-provider-secret)
- A NixOS image for Digital Ocean, built on another machine with nixpkgs image tooling

## Secrets

Two files are kept out of git and stored in 1Password (Private vault) as Documents:

- `secrets/secrets.crypt.nix` — agenix public key rules
- `nixos/systems/cube/secrets.crypt.nix` — cube host config

Pull them to disk after a fresh clone:

```sh
nix develop
secrets-pull
```

## Building a Base Image

```sh
nix build .#doImage
```

The resulting Digital Ocean image is linked at `result`.

## Running

If you've never run this before, you need to create some AWS resources to store the terraform state. We choose to store the state in the cloud to improve locking, and persist it between machines.

```sh
# make sure you have aws credentials in ~/.aws
cd terraform/tf-modules/terraform-state
terraform init
terraform apply
```

Now, you can run the rest of the deployment.

```sh
cp .env.example .env
$EDITOR .env # see variables.tf for advice on how to get certain vars
cd terraform
terraform init
terraform apply
```

## OCI Authentication

OCI credentials are kept outside this repo under `~/.oci`. The Terraform OCI
provider uses the short-lived security-token profile named `meatcar`.

```sh
nix develop
oci session authenticate --profile-name meatcar --session-expiration-in-minutes 60
oci session validate --profile meatcar --auth security_token
```

Set `TF_VAR_oci_region` from the selected OCI profile region and
`TF_VAR_oci_compartment_ocid` to the compartment containing the `chunkymonkey`
instance before importing or planning OCI resources.
