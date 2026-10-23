#!/usr/bin/env bash
data=$1
archive=$2
staging=$(mktemp "$(dirname "$archive")/.silverbullet-XXXXXX.tar")
trap 'rm -f "$staging"; systemctl --user start silverbullet.service' EXIT

# NOTE: Accounts, spaces and git refs change across files; copy them at rest.
systemctl --user stop silverbullet.service
tar -C "$data" -cf "$staging" .
mv "$staging" "$archive"
