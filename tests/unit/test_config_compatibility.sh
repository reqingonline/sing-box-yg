#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if ! command -v jq >/dev/null 2>&1; then
  echo 'config compatibility: SKIP (jq unavailable)'
  exit 0
fi
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/source.sh"
source "$repo_root/lib/config.sh"

cat > "$tmpdir/base.json" <<'EOF'
{
  "inbounds": [
    {"type":"vless","tag":"vless-sb","listen":"::","listen_port":18443},
    {"type":"hysteria2","tag":"hy2-sb","listen":"::","listen_port":18444},
    {"type":"tuic","tag":"tuic5-sb","listen":"::","listen_port":18445},
    {"type":"vmess","tag":"vmess-sb","listen":"::","listen_port":18080}
  ],
  "outbounds": [{"type":"direct","tag":"direct"}],
  "route": {
    "rule_set": [
      {"type":"remote","tag":"remote-test","url":"https://example.invalid/rules.srs","download_detour":"direct"}
    ],
    "rules": []
  }
}
EOF

sbyg_config_prepare "$tmpdir/base.json" "$tmpdir/v113.json" v1.13.12
jq -e '.dns.servers[] | select(.tag == "local" and .type == "local")' "$tmpdir/v113.json"
jq -e '.route.default_domain_resolver == "local"' "$tmpdir/v113.json"
jq -e 'has("http_clients") | not' "$tmpdir/v113.json"
jq -e '.route.rule_set[0].download_detour == "direct"' "$tmpdir/v113.json"

sbyg_config_prepare "$tmpdir/base.json" "$tmpdir/v114.json" v1.14.0-alpha.27
jq -e '.http_clients[] | select(.tag == "direct" and .engine == "go")' "$tmpdir/v114.json"
jq -e '.route.default_http_client == "direct"' "$tmpdir/v114.json"
jq -e '.route.default_domain_resolver == "local"' "$tmpdir/v114.json"
jq -e '.experimental.cache_file.enabled == true' "$tmpdir/v114.json"
jq -e '.experimental.cache_file.store_dns == true' "$tmpdir/v114.json"
jq -e '.route.rule_set[0] | has("download_detour") | not' "$tmpdir/v114.json"
jq -e '.route.rule_set[0].http_client == "direct"' "$tmpdir/v114.json"

echo 'sing-box configuration compatibility: PASS'
