#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/assert.sh"
fragment=$(mktemp)
log=$(mktemp)
bin=$(mktemp)
snapshot_log=$(mktemp)
restore_log=$(mktemp)
trap 'rm -f "$fragment" "$log" "$bin" "$snapshot_log" "$restore_log"' EXIT

sed -n '/^checksb(){/,/^stclre(){/p' "$repo_root/sb.sh" | sed '$d' > "$fragment"
red() { :; }
fail_stage=''
restart_calls=0
active_calls=0
systemctl() {
  printf '%s\n' "$*" >> "$log"
  case $1 in
    restart)
      restart_calls=$((restart_calls + 1))
      [ "$fail_stage" = restart ] && [ "$restart_calls" -eq 1 ] && return 1
      ;;
    is-active)
      active_calls=$((active_calls + 1))
      [ "$fail_stage" = active ] && [ "$active_calls" -eq 1 ] && return 1
      ;;
  esac
  return 0
}
source "$fragment"
sbfiles=''
snapshot_config() { printf 'snapshot\n' >> "$snapshot_log"; }
restore_config() { printf 'restore\n' >> "$restore_log"; }

printf '#!/usr/bin/env bash\nexit 1\n' > "$bin"
chmod +x "$bin"
SING_BOX_BIN="$bin"
if restartsb; then exit 1; fi
assert_not_called "$log"

printf '#!/usr/bin/env bash\nexit 0\n' > "$bin"
restartsb
grep -Fx 'restart sing-box' "$log"
grep -Fx 'is-active --quiet sing-box' "$log"
grep -Fx snapshot "$snapshot_log"

: > "$snapshot_log"
: > "$restore_log"
: > "$log"
restart_calls=0
active_calls=0
fail_stage=restart
if restartsb; then exit 1; fi
assert_not_called "$snapshot_log"
grep -Fx restore "$restore_log"

: > "$snapshot_log"
: > "$restore_log"
: > "$log"
restart_calls=0
active_calls=0
fail_stage=active
if restartsb; then exit 1; fi
assert_not_called "$snapshot_log"
grep -Fx restore "$restore_log"
