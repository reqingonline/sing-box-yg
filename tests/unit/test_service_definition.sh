#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/service.sh"
sbyg_service_render_systemd "$tmpdir/sing-box.service" \
  /tmp/sbyg-test/sing-box /tmp/sbyg-test/sb.json /tmp/sbyg-test
sbyg_service_render_health_timer "$tmpdir/health.service" "$tmpdir/health.timer" \
  /tmp/sbyg-test/sb-doctor.sh

unit="$tmpdir/sing-box.service"
grep -Fx 'After=network-online.target nss-lookup.target' "$unit"
grep -Fx 'Wants=network-online.target' "$unit"
grep -Fx 'NoNewPrivileges=true' "$unit"
grep -Fx 'PrivateTmp=true' "$unit"
grep -Fx 'ProtectSystem=strict' "$unit"
grep -Fx 'ProtectHome=read-only' "$unit"
grep -Fx 'ReadWritePaths=/tmp/sbyg-test' "$unit"
grep -Fx 'Restart=on-failure' "$unit"
grep -Fx 'OnUnitActiveSec=15min' "$tmpdir/health.timer"
grep -Fx 'ExecStart=/tmp/sbyg-test/sb-doctor.sh --repair' "$tmpdir/health.service"

if grep -nE '0 1 \* \* \* (systemctl|rc-service).*sing-box.*restart' "$repo_root/sb.sh"; then
  echo 'daily blind restart remains' >&2
  exit 1
fi

echo 'hardened service definition: PASS'
