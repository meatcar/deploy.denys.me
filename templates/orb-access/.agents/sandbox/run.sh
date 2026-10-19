#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

export SANDBOX_LIFECYCLE="$1"
version=3.48.0
task_dir="$HOME/.local/share/sandbox/task-v$version"

# shellcheck source=../access/env.sh
source .agents/access/env.sh

http_proxy_value="${HTTP_PROXY:-${http_proxy:-${npm_config_http_proxy:-}}}"
https_proxy_value="${HTTPS_PROXY:-${https_proxy:-${npm_config_https_proxy:-}}}"
[ -n "$http_proxy_value" ] || http_proxy_value="$https_proxy_value"
[ -n "$https_proxy_value" ] || https_proxy_value="$http_proxy_value"
if [ -n "$http_proxy_value" ]; then
  export HTTP_PROXY="$http_proxy_value" http_proxy="$http_proxy_value"
  export HTTPS_PROXY="$https_proxy_value" https_proxy="$https_proxy_value"
fi

if [ ! -x "$task_dir/task" ]; then
  if [ "$SANDBOX_LIFECYCLE" != setup ]; then
    echo 'Task unavailable; run .agents/setup' >&2
    exit 1
  fi
  case "$(uname -sm)" in
  'Linux x86_64')
    arch=amd64
    checksum=f4bfc4eef1b2557b262f3cc0a79976a421885cb7b9e71cfe75568a2ebe4d7ae5
    ;;
  'Linux aarch64')
    arch=arm64
    checksum=15a54fd45f706ce0f4c679c93cf04e02d72ca7223f157209201a1576008056d6
    ;;
  *)
    echo 'Task bootstrap requires x86_64 or aarch64 Linux' >&2
    exit 1
    ;;
  esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://github.com/go-task/task/releases/download/v$version/task_linux_$arch.tar.gz" -o "$tmp/task.tar.gz"
  printf '%s  %s\n' "$checksum" "$tmp/task.tar.gz" | sha256sum --check
  tar -xzf "$tmp/task.tar.gz" -C "$tmp" task
  mkdir -p "$task_dir"
  install -m 755 "$tmp/task" "$task_dir/task.tmp"
  mv "$task_dir/task.tmp" "$task_dir/task"
  rm -rf "$tmp"
  trap - EXIT
fi

export PATH="$task_dir:$HOME/.nix-profile/bin:$PATH"
if [ "$(id -u)" = 0 ]; then
  export NIX_CONFIG="${NIX_CONFIG:-}"$'\nbuild-users-group ='
fi
if [ "$SANDBOX_LIFECYCLE" = resume ]; then
  if [ ! -x "$HOME/.nix-profile/bin/nix" ] || ! command -v direnv >/dev/null 2>&1; then
    echo 'Devshell unavailable; run .agents/setup' >&2
    exit 1
  fi
fi

task=("$task_dir/task" --dir . --taskfile .agents/Taskfile.yml)
if [ "$SANDBOX_LIFECYCLE" = setup ]; then
  trap '"${task[@]}" setup_cleanup' EXIT
fi

"${task[@]}" before_nix
if [ "$SANDBOX_LIFECYCLE" = setup ]; then
  bash .agents/sandbox/nix.sh "$task_dir/task"
fi

direnv exec . "${task[@]}" "${SANDBOX_LIFECYCLE}_auth"
direnv exec . "${task[@]}" work
