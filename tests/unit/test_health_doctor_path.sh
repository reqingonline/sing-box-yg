#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
doctor="$repo_root/scripts/sb-doctor.sh"
test -x "$doctor"

grep -Fq '"${SBYG_INSTALL_ROOT:-/usr/local/lib/sing-box-yg}/scripts/sb-doctor.sh"' "$repo_root/sb.sh"
grep -Fq '${SBYG_INSTALL_ROOT:-/usr/local/lib/sing-box-yg}/scripts/sb-doctor.sh --repair' "$repo_root/sb.sh"
if grep -Fq '/usr/local/lib/sing-box-yg/sb-doctor.sh' "$repo_root/sb.sh"; then
  echo 'health timer still references the pre-release doctor path' >&2
  exit 1
fi

echo 'health doctor path: PASS'
