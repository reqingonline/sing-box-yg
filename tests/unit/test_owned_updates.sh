#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

if grep -RInE 'raw\.githubusercontent\.com/yonggekkk/sing-box-yg' \
  "$repo_root/sb.sh" "$repo_root/serv00.sh" "$repo_root/serv00keep.sh" "$repo_root/kp.sh"; then
  echo 'upstream executable or self-update URL remains' >&2
  exit 1
fi

test "$(awk '/^upsbyg\(\)/,/^}/' "$repo_root/sb.sh" | grep -c 'lnsb')" -eq 1

for artifact in "$repo_root"/*.zip "$repo_root"/sbwpph_amd64 "$repo_root"/sbwpph_arm64; do
  [ ! -e "$artifact" ] || {
    echo "opaque tracked artifact remains: ${artifact##*/}" >&2
    exit 1
  }
done

awk '/^lnsb\(\)/,/^}/' "$repo_root/sb.sh" | grep -F -- '--channel stable'
if awk '/^lnsb\(\)/,/^}/' "$repo_root/sb.sh" | grep -E 'curl|raw\.githubusercontent'; then
  echo 'self-update bypasses the verified installer' >&2
  exit 1
fi

if grep -E 'sshpass +-p|StrictHostKeyChecking=no|echo .*remote_command|grep .*ARGO_AUTH' "$repo_root/kp.sh"; then
  echo 'Serv00 automation exposes credentials or disables host-key verification' >&2
  exit 1
fi
if grep -E 'releases/latest/download/(cloudflared|geo(ip|site))' "$repo_root/sb.sh"; then
  echo 'release asset bypasses the GitHub digest check' >&2
  exit 1
fi

echo 'owned update paths: PASS'
