#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if ! command -v jq >/dev/null 2>&1; then
  echo 'core release selection: SKIP (jq unavailable)'
  exit 0
fi

source "$repo_root/lib/core_release.sh"
fixture='[
  {"tag_name":"v1.14.0-beta.14","draft":false,"prerelease":true},
  {"tag_name":"v1.13.18","draft":false,"prerelease":false},
  {"tag_name":"v1.13.99","draft":true,"prerelease":false},
  {"tag_name":"v1.14.0-alpha.1","draft":false,"prerelease":true}
]'
channels=$(sbyg_sing_box_release_channels "$fixture")
grep -Fx 'stable=1.13.18' <<<"$channels"
grep -Fx 'prerelease=1.14.0-beta.14' <<<"$channels"

if sbyg_sing_box_release_channels '{invalid' >/dev/null 2>&1; then
  echo 'release selector accepted malformed JSON' >&2
  exit 1
fi
grep -Fq 'sbyg_sing_box_release_channels' "$repo_root/sb.sh"
if grep -nE 'github\.com/SagerNet/sing-box/releases/latest|github\.com/SagerNet/sing-box/releases\"|data\.jsdelivr\.com/v1/package/gh/SagerNet/sing-box|grep -oP.*tag/v' "$repo_root/sb.sh"; then
  echo 'core release selection still depends on mutable HTML or jsDelivr parsing' >&2
  exit 1
fi

echo 'core release selection: PASS'
