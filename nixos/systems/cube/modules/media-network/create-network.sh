#!/usr/bin/env bash
set -euo pipefail
if ! docker network inspect media >/dev/null 2>&1; then
  docker network create media
fi
