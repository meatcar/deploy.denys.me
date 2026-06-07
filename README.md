# Infrastructure for denys.me

[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

## Requirements

- `direnv`
- `nix` or `nixos`

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
