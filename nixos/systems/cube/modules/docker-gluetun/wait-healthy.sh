#!/usr/bin/env bash
set -euo pipefail

until docker exec gluetun /gluetun-entrypoint healthcheck >/dev/null 2>&1; do
  sleep 1
done
