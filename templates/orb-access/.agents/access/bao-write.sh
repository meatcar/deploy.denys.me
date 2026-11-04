#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set +x
set -euo pipefail

usage() {
  echo 'Usage: bao-write.sh login | logout | put DOCUMENT KEY...' >&2
  exit 1
}
: "${BAO_PROJECT:?Set BAO_PROJECT to the project owner/repository}"
# shellcheck source=env.sh
source "$(dirname "$0")/env.sh"
caller_token="${BAO_TOKEN:-}"
unset BAO_TOKEN VAULT_TOKEN
name="${BAO_PROJECT/\//--}"
token_file="${XDG_RUNTIME_DIR:?Set XDG_RUNTIME_DIR to a private runtime directory}/bao-write--$name"
login_hint="Run: task --dir . --taskfile .agents/Taskfile.yml access:bao-write -- login"

revoke() {
  [ -s "$token_file" ] || return 0
  BAO_TOKEN="$(cat "$token_file")" bao token revoke -self >/dev/null 2>&1 || true
  rm -f "$token_file"
}

minter_login() {
  local login=(bao write -field=token auth/userpass/login/bao-minter password=-)
  if [ -n "${BAO_MINTER_PASSWORD_REF:-}" ]; then
    op read --no-newline "$BAO_MINTER_PASSWORD_REF" | "${login[@]}"
    return
  fi
  local password=''
  IFS= read -rsp 'bao-minter password: ' password || true
  echo >&2
  [ -n "$password" ] || {
    echo 'Empty password.' >&2
    return 1
  }
  printf '%s' "$password" | "${login[@]}"
}

case "${1:-}" in
login)
  [ "$#" = 1 ] || usage
  revoke
  minter="$(minter_login)"
  trap 'rm -f "${scoped:-}"; BAO_TOKEN="$minter" bao token revoke -self >/dev/null' EXIT
  scoped="$(mktemp "$token_file.XXXXXX")"
  BAO_TOKEN="$minter" bao token create -role="project--$name--write" -field=token >"$scoped"
  mv "$scoped" "$token_file"
  echo "15-minute write token for $BAO_PROJECT: $token_file" >&2
  ;;
logout)
  [ "$#" = 1 ] || usage
  revoke
  ;;
put)
  [ "$#" -ge 3 ] || usage
  document="$2"
  shift 2
  if [ -z "$caller_token" ] && [ ! -s "$token_file" ]; then
    echo "No write token. $login_hint" >&2
    exit 1
  fi
  data='{}'
  for key; do
    value=''
    if [ -t 0 ]; then
      IFS= read -rsp "$key: " value
      echo >&2
    else
      IFS= read -r value || true
    fi
    [ -n "$value" ] || {
      echo "Empty value for $key." >&2
      exit 1
    }
    data="$(printf '%s' "$data" | KEY="$key" VALUE="$value" jq -c '.[env.KEY] = env.VALUE')"
  done
  if [ ! -t 0 ] && { IFS= read -r extra || [ -n "${extra:-}" ]; }; then
    echo 'More input lines than keys.' >&2
    exit 1
  fi
  BAO_TOKEN="${caller_token:-$(cat "$token_file")}"
  export BAO_TOKEN
  mount="projects/$BAO_PROJECT"
  # NOTE: Create-only first; patch never drops keys this token cannot read.
  printf '%s' "$data" | bao kv put -mount="$mount" -cas=0 "$document" - 2>/dev/null ||
    printf '%s' "$data" | bao kv patch -mount="$mount" "$document" - || {
    echo "Write failed: prod is create-only, and only agent_writes documents are writable. Expired? $login_hint" >&2
    exit 1
  }
  ;;
*) usage ;;
esac
