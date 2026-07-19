#!/usr/bin/env bash
set -euo pipefail
core=${SBYG_ACCEPTANCE_CORE:?set SBYG_ACCEPTANCE_CORE}
config=${SBYG_ACCEPTANCE_CONFIG:?set SBYG_ACCEPTANCE_CONFIG}
unit=${SBYG_ACCEPTANCE_UNIT:-sbyg-acceptance.service}
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT
cp "$config" "$workdir/healthy.json"
healthy_hash=$(sha256sum "$config" | awk '{print $1}')
printf '{invalid\n' > "$workdir/invalid.json"
! "$core" check -c "$workdir/invalid.json" >/dev/null 2>&1
systemctl is-active --quiet "$unit"
jq '(.inbounds[0].listen_port)=22' "$workdir/healthy.json" > "$config"
"$core" check -c "$config"
systemctl restart "$unit" || true; sleep 2
! systemctl is-active --quiet "$unit"
cp "$workdir/healthy.json" "$config"
systemctl restart "$unit"; systemctl is-active --quiet "$unit"
test "$(sha256sum "$config" | awk '{print $1}')" = "$healthy_hash"
echo 'invalid JSON and port-conflict rollback: PASS'
