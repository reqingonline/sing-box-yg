#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/transaction.sh"

printf 'old-config\n' > "$tmpdir/config"
printf '#!/bin/sh\nprintf "old-core\\n"\n' > "$tmpdir/core"
chmod +x "$tmpdir/core"
sbyg_transaction_begin "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"

printf 'new-config\n' > "$tmpdir/config"
printf '#!/bin/sh\nprintf "new-core\\n"\n' > "$tmpdir/core"
chmod +x "$tmpdir/core"

restart_calls=0
sbyg_validate_config() { return 0; }
sbyg_service_restart() {
  restart_calls=$((restart_calls + 1))
  [ "$restart_calls" -gt 1 ]
}
sbyg_service_active() { return 0; }
sbyg_expected_ports_listening() { return 0; }

if sbyg_transaction_apply "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"; then
  echo 'failed restart committed the transaction' >&2
  exit 1
fi
grep -Fx old-config "$tmpdir/config"
grep -F 'old-core' "$tmpdir/core"
test ! -e "$tmpdir/state/committed"

sbyg_transaction_begin "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"
printf 'healthy-config\n' > "$tmpdir/config"
restart_calls=1
sbyg_transaction_apply "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"
test -e "$tmpdir/state/committed"
grep -Fx healthy-config "$tmpdir/config"

echo 'transaction rollback: PASS'
