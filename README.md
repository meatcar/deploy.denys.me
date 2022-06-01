# Infrastructure for denys.me

[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

## Requirements

- `direnv`
- `nix` or `nixos`

If `nix` is not available, you can try to make do with:

- `packer`
- `terraform` with [terraform-provider-secret](https://github.com/tweag/terraform-provider-secret)
- A nixos image for Digital Ocean, you can try to make one with `packer` and `nix-infect` as follows:

  ```sh
  packer build packer/build-image.json
  ```

  Then manually make a snapshot of it in the Digital Ocean console.

## Building a Base Image

```sh
# Build an image
IMAGE=$(nixos-generate -f do -c nix/base.nix)
# Push the image to Digital Ocean
packer build -var image=$IMAGE packer/push-image.json
```

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
