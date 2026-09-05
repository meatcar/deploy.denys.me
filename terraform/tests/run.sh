#!/usr/bin/env bash
set -euo pipefail

repo=$(realpath "$(dirname "$0")/../..")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

ln -s "$repo/packages" "$scratch/packages"
ln -s "$repo/nixos" "$scratch/nixos"

for name in netbird bao-config bao; do
  source_dir="$repo/terraform/$name"
  test_dir="$scratch/terraform/$name"
  mkdir -p "$test_dir"
  for file in "$source_dir"/*.tf "$source_dir"/*.tftest.hcl "$source_dir/.terraform.lock.hcl"; do
    # NOTE: OpenTofu 1.11 crashes when mock providers process import blocks.
    [[ $(basename "$file") == imports.tf ]] || cp "$file" "$test_dir/"
  done
  TF_DATA_DIR="$source_dir/.terraform" terraform -chdir="$test_dir" test -no-color
done
