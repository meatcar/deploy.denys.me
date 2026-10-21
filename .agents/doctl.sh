#!/usr/bin/env bash
set +x
set -euo pipefail

DIGITALOCEAN_ACCESS_TOKEN="$(
  bao kv get -format=json -mount=projects/meatcar/deploy.denys.me prod/plan/digitalocean |
    jq -er '.data.data.TF_VAR_digitalocean_token | strings | select(length > 0)'
)"
export DIGITALOCEAN_ACCESS_TOKEN
unset BAO_TOKEN VAULT_TOKEN
exec doctl "$@"
