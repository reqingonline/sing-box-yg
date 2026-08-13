#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
serv00="$repo_root/serv00.sh"
keep="$repo_root/serv00keep.sh"

for file in "$serv00" "$keep"; do
  bash -n "$file"
  grep -F 'sbyg_serv00_port_from_config()' "$file"
  grep -F 'sbyg_serv00_argo_fixed' "$file"
  if grep -E 'ARGO_AUTH[[:space:]]*=~' "$file"; then
    echo "Argo fixed-mode detection still depends on a narrow token regex: $file" >&2
    exit 1
  fi
done

grep -F '"type": "commonjs"' "$repo_root/package.json"
grep -F 'package.json' "$repo_root/kp.sh"
grep -F 'package.json' "$serv00"
grep -F 'package.json' "$keep"
grep -F 'argoport=$(sbyg_serv00_port_from_config vmess-sb config.json)' "$serv00"
grep -F 'TUNNEL_TOKEN="$token"' "$serv00"
grep -F 'TUNNEL_TOKEN="$token"' "$keep"
if grep -E 'green .*ARGO_AUTH|purple .*ARGO_AUTH' "$serv00" "$keep"; then
  echo 'Argo token is echoed by a user-facing status message' >&2
  exit 1
fi
if grep -E '(printf|echo|tee)[^\n]*ARGO_AUTH_show\.log' "$serv00" "$keep"; then
  echo 'Argo token is copied into the legacy show file' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo 'Serv00 compatibility: PASS (jq unavailable; tag-port runtime check skipped)'
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
sed -n '/^sbyg_serv00_port_from_config()/,/^}$/p' "$serv00" > "$tmpdir/helper.sh"
source "$tmpdir/helper.sh"
cat > "$tmpdir/reordered.json" <<'EOF'
{
  "inbounds": [
    {"tag":"anytls-sb","listen_port":10006},
    {"tag":"vmess-sb","listen_port":18080},
    {"tag":"hy2-sb","listen_port":18444},
    {"tag":"vless-sb","listen_port":18443}
  ]
}
EOF
test "$(sbyg_serv00_port_from_config vmess-sb "$tmpdir/reordered.json")" = 18080
test "$(sbyg_serv00_port_from_config vless-sb "$tmpdir/reordered.json")" = 18443
if sbyg_serv00_port_from_config missing-tag "$tmpdir/reordered.json"; then
  echo 'missing inbound tag unexpectedly returned a port' >&2
  exit 1
fi

echo 'Serv00 compatibility: PASS'
