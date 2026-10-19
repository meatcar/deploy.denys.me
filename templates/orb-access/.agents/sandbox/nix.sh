#!/usr/bin/env bash
# Provision Nix, direnv, and future shell integration for a disposable sandbox.
# Takes the Task executable path as its first argument.
set -euo pipefail

if [ ! -x "$HOME/.nix-profile/bin/nix" ]; then
  installer="$(mktemp)"
  curl -fsSL https://nixos.org/nix/install -o "$installer"
  sh "$installer" --no-daemon --yes --no-channel-add
  rm -f "$installer"
  # shellcheck source=/dev/null
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

mkdir -p "$HOME/.config/nix"
touch "$HOME/.config/nix/nix.conf"
grep -Fqx 'sandbox = false' "$HOME/.config/nix/nix.conf" ||
  printf '%s\n' 'sandbox = false' >>"$HOME/.config/nix/nix.conf"
grep -Eq '^experimental-features = .*nix-command.*flakes' "$HOME/.config/nix/nix.conf" ||
  printf '%s\n' 'experimental-features = nix-command flakes' >>"$HOME/.config/nix/nix.conf"

command -v direnv >/dev/null 2>&1 || nix profile install --inputs-from . nixpkgs#direnv
direnv allow .

agent_env="$HOME/.sandbox-env.sh"
printf "export PATH=%q:\$PATH\n" "$(dirname "$1"):$HOME/.nix-profile/bin" >"$agent_env"
printf 'source %q\n' "$PWD/.agents/access/env.sh" >>"$agent_env"
cat >>"$agent_env" <<'EOF'
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
EOF

if ! grep -Fq '.sandbox-env.sh' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

[ -f "$HOME/.sandbox-env.sh" ] && . "$HOME/.sandbox-env.sh"
EOF
fi

marker="# sandbox environment: $PWD"
if ! grep -Fqx "$marker" "$HOME/.bash_profile" 2>/dev/null; then
  {
    printf "\n%s\nif [[ \$PWD == %q || \$PWD == %q/* ]]; then\n" "$marker" "$PWD" "$PWD"
    cat <<'EOF'
  [ -f "$HOME/.sandbox-env.sh" ] && . "$HOME/.sandbox-env.sh"
  if command -v direnv >/dev/null 2>&1; then
    direnv allow . >/dev/null 2>&1
    eval "$(direnv export bash 2>/dev/null)"
  fi
fi
EOF
  } >>"$HOME/.bash_profile"
fi
