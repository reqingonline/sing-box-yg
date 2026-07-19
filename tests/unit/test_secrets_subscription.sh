#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
http_log="$tmpdir/http.log"

source "$repo_root/lib/secrets.sh"
source "$repo_root/lib/subscription.sh"

for name in argo telegram gitlab subscription; do
  sbyg_write_secret "$tmpdir/secrets/$name" "${name}-not-a-real-secret"
  test "$(sbyg_read_secret "$tmpdir/secrets/$name")" = "${name}-not-a-real-secret"
  case $(uname -s) in
    MINGW*|MSYS*) ;;
    *) sbyg_assert_private_file "$tmpdir/secrets/$name" ;;
  esac
done

token=$(sbyg_subscription_token)
case $token in
  *[!0-9a-f]*|'') echo 'subscription token is not random hex' >&2; exit 1 ;;
esac
test "${#token}" -eq 48
test "$token" != '11111111-1111-1111-1111-111111111111'
test "$(sbyg_subscription_url_redacted 18080 "$token")" = \
  "http://127.0.0.1:18080/${token:0:4}...${token:44:4}/"
test "$(sbyg_redact_url 'https://example.invalid/file?private_token=topsecret&ref=main')" = \
  'https://example.invalid/file?private_token=[redacted]&ref=main'

busybox() { printf '%s\n' "$*" >> "$http_log"; }
mkdir -p "$tmpdir/web"
pid=$(sbyg_subscription_start_loopback "$tmpdir/web" 18080 "$tmpdir/httpd.log")
wait "$pid" 2>/dev/null || true
grep -Fx 'httpd -f -p 127.0.0.1:18080 -h '"$tmpdir/web" "$http_log"

if sbyg_subscription_public_url 'http://example.invalid' "$token" clmi.yaml; then
  echo 'public HTTP subscription was accepted' >&2
  exit 1
fi
test "$(sbyg_subscription_public_url 'https://sub.example.invalid' "$token" clmi.yaml)" = \
  "https://sub.example.invalid/$token/clmi.yaml"

grep -F -- '--token-file /etc/s-box/.secrets/argo-token' "$repo_root/sb.sh"
if grep -F 'https://${token}@gitlab.com' "$repo_root/sb.sh"; then
  echo 'Git remote still embeds an access token' >&2
  exit 1
fi
if grep -E 'httpd -f -p ["$({]*[0-9]' "$repo_root/sb.sh" | grep -v '127\.0\.0\.1:'; then
  echo 'subscription server can bind publicly' >&2
  exit 1
fi

echo 'secret and subscription protection: PASS'
