#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
for command_name in bash jq sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "integration smoke: SKIP ($command_name unavailable)"
    exit 0
  }
done

tmpdir=$(mktemp -d)
service_pid=
cleanup() {
  test -z "$service_pid" || kill "$service_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

source "$repo_root/lib/cleanup.sh"
source "$repo_root/lib/transaction.sh"

root="$tmpdir/root"
state="$root/state"
core="$root/sing-box"
config="$root/config.json"
manifest="$root/assets.v1"
mkdir -p "$root"
cp "$repo_root/tests/fixtures/fake-sing-box" "$core"
chmod 755 "$core"
printf '{"inbounds":[],"test_invalid":false}\n' > "$config"
chmod 600 "$config"

sbyg_service_restart() {
  test -z "$service_pid" || kill "$service_pid" 2>/dev/null || true
  "$core" run -c "$config" &
  service_pid=$!
}
sbyg_service_active() { kill -0 "$service_pid" 2>/dev/null; }
sbyg_expected_ports_listening() { return 0; }

sbyg_transaction_begin "$state" "$config" "$core"
printf '{"inbounds":[],"generation":2,"test_invalid":false}\n' > "$config"
sbyg_transaction_apply "$state" "$config" "$core"
test -f "$state/committed"
jq -e '.generation == 2' "$config" >/dev/null

rm -rf "$state"
sbyg_transaction_begin "$state" "$config" "$core"
printf '{"inbounds":[],"generation":3,"test_invalid":true}\n' > "$config"
if sbyg_transaction_apply "$state" "$config" "$core"; then
  echo 'invalid candidate unexpectedly committed' >&2
  exit 1
fi
jq -e '.generation == 2 and .test_invalid == false' "$config" >/dev/null

owned="$root/owned.txt"
sentinel="$root/unrelated.txt"
printf owned > "$owned"
printf keep > "$sentinel"
sbyg_manifest_add "$manifest" "$root" "$owned"
sbyg_cleanup_manifest "$manifest" "$root"
test ! -e "$owned"
grep -Fx keep "$sentinel"

echo 'install/update/rollback/uninstall smoke: PASS'
