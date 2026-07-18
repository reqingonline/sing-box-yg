#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
command -v docker >/dev/null 2>&1 || {
  echo 'distribution matrix: SKIP (docker unavailable; CI runs the real matrix)'
  exit 0
}

for image in ubuntu:22.04 ubuntu:24.04 debian:12 alpine:3.20; do
  docker run --rm -v "$repo_root:/repo:ro" "$image" sh -c '
    if command -v apk >/dev/null; then apk add --no-cache bash jq coreutils; else apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash jq coreutils; fi
    bash /repo/tests/integration/install-smoke.sh
  '
done
