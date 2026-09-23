#!/usr/bin/env bash
set -euo pipefail
: "${src:?}" "${out:?}"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/positive" "$scratch/negative"
scanner=(gitleaks dir --no-banner --no-color --redact=100 --ignore-gitleaks-allow --gitleaks-ignore-path=/dev/null)

printf -v digest '%086d' 0
printf 'hashedPassword = "%s";\n' "\$6\$audit\$$digest" >"$scratch/positive/configuration.nix"
printf -- '-----BEGIN %s-----\n%s\n-----END %s-----\n' 'PRIVATE KEY' "$digest" 'PRIVATE KEY' >"$scratch/positive/key.pem"

set +e
"${scanner[@]}" "$scratch/positive" --exit-code=23 --report-format=json --report-path="$scratch/findings.json"
status=$?
set -e
test "$status" -eq 23
jq -e 'any(.[]; .RuleID == "unix-password-hash") and any(.[]; .RuleID == "private-key")' "$scratch/findings.json" >/dev/null

printf 'hashedPasswordFile = "/run/agenix/hashedPassword";\n' >"$scratch/negative/configuration.nix"
"${scanner[@]}" "$scratch/negative"
"${scanner[@]}" "$src"
touch "$out"
