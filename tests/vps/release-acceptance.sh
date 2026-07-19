#!/usr/bin/env bash
set -euo pipefail
core=${SBYG_ACCEPTANCE_CORE:?set SBYG_ACCEPTANCE_CORE}
config=${SBYG_ACCEPTANCE_CONFIG:?set SBYG_ACCEPTANCE_CONFIG}
unit=${SBYG_ACCEPTANCE_UNIT:-sbyg-acceptance.service}
"$core" check -c "$config"
systemctl restart "$unit"
for _ in 1 2 3 4 5 6; do sleep 10; systemctl is-active --quiet "$unit"; done
ss -H -lntup | grep -qE ':28443|:28444'
! journalctl -u "$unit" --since '-2 min' --no-pager | grep -q 'Start request repeated too quickly'
echo 'real core service acceptance: PASS'
