#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fragment="$tmpdir/functions.sh"

sed -n '/^download_to_temp(){/,/^inssb(){/p' "$repo_root/sb.sh" | sed '$d' > "$fragment"
source "$fragment"

first="$tmpdir/first.json"
second="$tmpdir/second.json"
printf '%s\n' '{"inbounds":[{"tag":"vmess-sb","listen_port":10001},{"tag":"vless-sb","listen_port":10002},{"tag":"hy2-sb","listen_port":10003}]}' > "$first"
printf '%s\n' '{"inbounds":[{"tag":"tuic5-sb","listen_port":10004},{"tag":"vless-sb","listen_port":10005},{"tag":"anytls-sb","listen_port":10006}]}' > "$second"
chmod 640 "$first"
sbfiles="$first $second"

update_inbound_port vless-sb 18443
test "$(jq -r '.inbounds[] | select(.tag == "vless-sb") | .listen_port' "$first")" = 18443
test "$(jq -r '.inbounds[] | select(.tag == "vless-sb") | .listen_port' "$second")" = 18443
case $(uname -s) in
  MINGW*|MSYS*) ;;
  *) test "$(stat -c %a "$first")" = 640 ;;
esac

before=$(sha256sum "$first" "$second")
if update_inbound_port missing-tag 18444; then exit 1; fi
if update_inbound_port vless-sb invalid-port; then exit 1; fi
after=$(sha256sum "$first" "$second")
test "$before" = "$after"
