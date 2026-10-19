#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set +x
set -euo pipefail

if [ "$#" = 0 ]; then
  echo 'Usage: bao.sh command [args...]' >&2
  exit 1
fi
: "${BAO_ROLE:?Set BAO_ROLE to the project JWT role}"
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"
unset BAO_TOKEN VAULT_TOKEN

BAO_TOKEN="$(
  amp orb id-token --audience bao --subject-scope project --ttl-seconds 300 |
    bao write -format=json auth/amp/login role="$BAO_ROLE" jwt=- |
    jq -er '.auth.client_token | strings | select(length > 0)'
)"
export BAO_TOKEN
exec "$@"
