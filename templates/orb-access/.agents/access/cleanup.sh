#!/usr/bin/env bash
set +x
set -euo pipefail

if [ -f /etc/systemd/system/amp-orb-netbird.service ]; then
  sudo systemctl disable --now amp-orb-netbird.service
fi
# NOTE: Orb snapshots can preserve /run.
sudo rm -rf /run/amp-orb-netbird /run/amp-orb-access
rm -f "$HOME/.bao-token" "$HOME/.vault-token"
rm -rf "$HOME/.aws/cli/cache" "$HOME/.aws/sso/cache"
