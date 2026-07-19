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

if grep -E 'sshpass +(-p|-e)|SSHPASS=|StrictHostKeyChecking=no|echo .*remote_command|grep .*ARGO_AUTH' \
  "$repo_root/kp.sh" "$repo_root/SSH.yml"; then
  echo 'Serv00 automation exposes credentials or disables host-key verification' >&2
  exit 1
fi
grep -F 'ACCOUNTS_JSON: ${{ secrets.SERV00_ACCOUNTS }}' "$repo_root/SSH.yml"
grep -F 'KNOWN_HOSTS: ${{ secrets.SERV00_KNOWN_HOSTS }}' "$repo_root/SSH.yml"
grep -F 'KNOWN_HOSTS: ${{ secrets.SERV00_KNOWN_HOSTS }}' "$repo_root/serv00.yml"
if grep -E 'rm +-rf|kill +-9|pkill|--token( |$)|cat +domains/.*/logs/list\.txt' \
  "$repo_root/serv00.sh" "$repo_root/serv00keep.sh" "$repo_root/kp.sh" "$repo_root/app.js"; then
  echo 'Serv00 automation still contains unowned cleanup, broad process kills, or secret output' >&2
  exit 1
fi
grep -F 'TUNNEL_TOKEN="$token"' "$repo_root/serv00.sh"
grep -F 'TUNNEL_TOKEN="$token"' "$repo_root/serv00keep.sh"
if grep -Eq '"private_key":[[:space:]]*"[A-Za-z0-9+/]{43}="' "$repo_root/serv00keep.sh"; then
  echo 'Serv00 script embeds a reusable private key' >&2
  exit 1
fi
grep -F 'SBYG_WARP_PRIVATE_KEY' "$repo_root/serv00keep.sh"
grep -F 'if [[ "$warp_enabled" == 1 ]]' "$repo_root/serv00keep.sh"
grep -F 'sbyg_serv00_verify_dependency' "$repo_root/serv00.sh"
grep -F 'sbyg_serv00_verify_dependency' "$repo_root/serv00keep.sh"
grep -F 'serv00-assets.sha256' "$repo_root/kp.sh"
grep -F 'lib/cleanup.sh lib/secrets.sh' "$repo_root/kp.sh"
grep -F 'fd9578820fcc96fe478e14a02750bd1aec331fa8446d3c58608cbf2a0c0f081c  sb' \
  "$repo_root/serv00-assets.sha256"
grep -F 'df31404b55ccfa76ed134b0f68e54f656a574d3abc0f5002ada8711131f981db  server' \
  "$repo_root/serv00-assets.sha256"
if grep -E "require\\(['\"](express|dotenv)['\"]\\)|npm install" \
  "$repo_root/app.js" "$repo_root/serv00.sh" "$repo_root/serv00keep.sh"; then
  echo 'Serv00 web keepalive still has unnecessary runtime packages' >&2
  exit 1
fi
if grep -E 'ps aux|child_process.*exec|\bexec\(' "$repo_root/app.js"; then
  echo 'Serv00 web keepalive still exposes process data or invokes a shell command string' >&2
  exit 1
fi
grep -F 'route.length !== 2 || !tokenMatches(route[1])' "$repo_root/app.js"
grep -F 'server.listen(listenPort, "127.0.0.1"' "$repo_root/app.js"
test "$(cat "$repo_root/RELEASE_VERSION")" = 'v1.0.0'
grep -F 'branches:' "$repo_root/.github/workflows/release.yml"
grep -F 'RELEASE_VERSION' "$repo_root/.github/workflows/release.yml"
grep -F '.github/workflows/release.yml' "$repo_root/.github/workflows/release.yml"
grep -F 'git merge-base --is-ancestor "$GITHUB_SHA" refs/remotes/origin/main' \
  "$repo_root/.github/workflows/release.yml"
grep -F 'bash scripts/publish-release.sh "$RELEASE_TAG" "$GITHUB_SHA"' \
  "$repo_root/.github/workflows/release.yml"
grep -F 'Authorization: Bearer $GH_TOKEN' "$repo_root/scripts/publish-release.sh"
grep -F 'draft:true' "$repo_root/scripts/publish-release.sh"
grep -F "printf '{\"draft\":false}" "$repo_root/scripts/publish-release.sh"
if grep -F 'gh api --method POST "repos/$GITHUB_REPOSITORY/git/tags"' \
  "$repo_root/.github/workflows/release.yml"; then
  echo 'release workflow uses the failed standalone annotated-tag API path' >&2
  exit 1
fi
if grep -E 'releases/latest/download/(cloudflared|geo(ip|site))' "$repo_root/sb.sh"; then
  echo 'release asset bypasses the GitHub digest check' >&2
  exit 1
fi

echo 'owned update paths: PASS'
