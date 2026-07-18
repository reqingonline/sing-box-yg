#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/lib/source.sh"
source "$repo_root/lib/download.sh"
source "$repo_root/lib/secrets.sh"

test "$SBYG_REPOSITORY" = "reqingonline/sing-box-yg"
test "$(sbyg_raw_url main sb.sh)" = \
  "https://raw.githubusercontent.com/reqingonline/sing-box-yg/main/sb.sh"
test "$(sbyg_release_api_url latest)" = \
  "https://api.github.com/repos/reqingonline/sing-box-yg/releases/latest"
test "$(sbyg_release_asset_url v1.2.3 bundle.tar.gz)" = \
  "https://github.com/reqingonline/sing-box-yg/releases/download/v1.2.3/bundle.tar.gz"
sbyg_version_at_least v1.14.0 v1.13.9
if sbyg_version_at_least v1.13.9 v1.14.0; then
  echo 'semantic version comparison is reversed' >&2
  exit 1
fi
if sbyg_raw_url main '../secret'; then
  echo 'repository path traversal was accepted' >&2
  exit 1
fi

if sbyg_require_https 'http://example.invalid/file'; then
  echo 'plain HTTP was accepted' >&2
  exit 1
fi
sbyg_require_https 'https://example.invalid/file'

printf old > "$tmpdir/current"
printf candidate > "$tmpdir/candidate"
printf '%064d  candidate\n' 0 > "$tmpdir/checksums.txt"
if sbyg_verify_checksum "$tmpdir/candidate" "$tmpdir/checksums.txt"; then
  echo 'invalid checksum was accepted' >&2
  exit 1
fi
grep -Fx old "$tmpdir/current"

digest=$(sha256sum "$tmpdir/candidate" | awk '{print $1}')
printf '%s  candidate\n' "$digest" > "$tmpdir/checksums.txt"
sbyg_verify_checksum "$tmpdir/candidate" "$tmpdir/checksums.txt"
sbyg_atomic_install "$tmpdir/candidate" "$tmpdir/current" 700
grep -Fx candidate "$tmpdir/current"

test "$(sbyg_redact 'abcdefghijklmnop')" = 'abcd...mnop'
test "$(sbyg_redact 'short')" = '[redacted]'
sbyg_write_secret "$tmpdir/secrets/token" 'not-a-real-token'
test "$(sbyg_read_secret "$tmpdir/secrets/token")" = 'not-a-real-token'
case $(uname -s) in
  MINGW*|MSYS*) ;;
  *) sbyg_assert_private_file "$tmpdir/secrets/token" ;;
esac

write_marker() { printf locked > "$1"; }
sbyg_with_lock "$tmpdir/locks/install.lock" write_marker "$tmpdir/locked"
grep -Fx locked "$tmpdir/locked"

echo 'source/download/secrets primitives: PASS'
