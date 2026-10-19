#!/usr/bin/env bash
set +x
set -euo pipefail

netbird_command() {
  sudo timeout --kill-after=5s 60s netbird \
    --daemon-addr unix:///run/amp-orb-netbird/netbird.sock "$@"
}

case "${1:-}" in
setup)
  sudo tee /etc/systemd/system/amp-orb-netbird.service >/dev/null <<EOF
[Unit]
Description=NetBird client for Amp orbs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
RuntimeDirectory=amp-orb-netbird
RuntimeDirectoryMode=0700
Environment=NB_STATE_DIR=/run/amp-orb-netbird
Environment=NB_CONFIG=/run/amp-orb-netbird/default.json
Environment=NB_DNS_STATE_FILE=/run/amp-orb-netbird/state.json
Environment=NB_DAEMON_ADDR=unix:///run/amp-orb-netbird/netbird.sock
Environment=NB_USE_NETSTACK_MODE=false
ExecStart=$(command -v netbird) service run --disable-profiles --log-file console
Restart=on-failure
RestartSec=2
EOF
  sudo systemctl daemon-reload
  ;;
resume)
  setup_key="${NETBIRD_SETUP_KEY:-}"
  unset NETBIRD_SETUP_KEY
  sudo systemctl start amp-orb-netbird.service
  if ! netbird_command status --json |
    jq -e '.daemonStatus == "Connected" and .management.connected == true' >/dev/null; then
    : "${setup_key:?Set the Amp project secret NETBIRD_SETUP_KEY}"
    sudo install -d -m 0700 -o "$(id -u)" /run/amp-orb-access
    umask 077
    key_file="$(mktemp /run/amp-orb-access/setup-key.XXXXXX)"
    trap 'rm -f "$key_file"' EXIT
    printf '%s' "$setup_key" >"$key_file"
    unset setup_key
    thread_suffix="${AMP_THREAD_ID:-orb}"
    thread_suffix="${thread_suffix##*-}"
    netbird_command up --setup-key-file "$key_file" \
      --management-url "${NETBIRD_MANAGEMENT_URL:-https://api.netbird.io:443}" \
      --hostname "amp-orb-${thread_suffix:0:12}" \
      --block-inbound --disable-client-routes --disable-server-routes >/dev/null
  fi
  ;;
*)
  echo 'Usage: netbird.sh setup|resume' >&2
  exit 1
  ;;
esac
