#!/usr/bin/env bash
set -euo pipefail

repo=$(realpath "$(dirname "$0")/../..")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

ln -s "$repo/packages" "$scratch/packages"
ln -s "$repo/nixos" "$scratch/nixos"

while IFS= read -r -d '' source_dir; do
  test_dir="$scratch/${source_dir#"$repo/"}"
  mkdir -p "$test_dir"
  for file in "$source_dir"/*.tf "$source_dir"/*.tftest.hcl "$source_dir/.terraform.lock.hcl"; do
    # NOTE: OpenTofu 1.11 crashes when mock providers process import blocks.
    [[ $(basename "$file") == imports.tf ]] || cp "$file" "$test_dir/"
  done
  TF_DATA_DIR="$source_dir/.terraform" tofu -chdir="$test_dir" test -no-color
done < <(find "$repo/terraform" -name .terraform -prune -o -name '*.tftest.hcl' -printf '%h\0' | sort -zu)
