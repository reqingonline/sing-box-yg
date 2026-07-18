#!/usr/bin/env bash

sbyg_require_https() {
  case ${1-} in
    https://*) return 0 ;;
    http://127.0.0.1:*|http://localhost:*)
      [ "${SBYG_ALLOW_INSECURE_TEST_URL:-0}" = 1 ] && return 0
      ;;
  esac
  printf 'refusing non-HTTPS URL: %s\n' "${1-}" >&2
  return 2
}

sbyg_verify_checksum() {
  local file=${1-} checksums=${2-} base expected actual
  [ -f "$file" ] && [ -s "$file" ] || {
    printf 'checksum target is missing or empty: %s\n' "$file" >&2
    return 2
  }
  [ -f "$checksums" ] || {
    printf 'checksum manifest is missing: %s\n' "$checksums" >&2
    return 2
  }
  base=${file##*/}
  expected=$(awk -v name="$base" \
    '$2 == name || $2 == ("*" name) { print tolower($1); exit }' "$checksums")
  case $expected in
    ''|*[!0-9a-f]* )
      printf 'valid checksum entry not found for %s\n' "$base" >&2
      return 2
      ;;
  esac
  [ "${#expected}" -eq 64 ] || {
    printf 'invalid SHA-256 length for %s\n' "$base" >&2
    return 2
  }
  actual=$(sha256sum "$file" | awk '{print tolower($1)}') || return
  [ "$actual" = "$expected" ] || {
    printf 'SHA-256 mismatch for %s\n' "$base" >&2
    return 1
  }
}

sbyg_atomic_install() {
  local candidate=${1-} destination=${2-} mode=${3:-600}
  local parent temporary
  [ -f "$candidate" ] && [ -s "$candidate" ] || {
    printf 'candidate is missing or empty: %s\n' "$candidate" >&2
    return 2
  }
  [ -n "$destination" ] && [ "$destination" != / ] || {
    printf 'unsafe destination: %s\n' "$destination" >&2
    return 2
  }
  parent=${destination%/*}
  [ "$parent" != "$destination" ] || parent=.
  mkdir -p "$parent" || return
  temporary="$parent/.${destination##*/}.sbyg.$$"
  umask 077
  rm -f "$temporary"
  if ! cp -- "$candidate" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! chmod "$mode" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! mv -f -- "$temporary" "$destination"; then
    rm -f "$temporary"
    return 1
  fi
}

sbyg_download() {
  local url=${1-} destination=${2-}
  sbyg_require_https "$url" || return
  [ -n "$destination" ] || return 2
  curl --fail --show-error --silent --location \
    --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 300 \
    --retry 3 --retry-delay 2 --output "$destination" "$url"
}

sbyg_download_verified() {
  local url=${1-} checksum_url=${2-} destination=${3-} mode=${4:-600}
  local tmpdir candidate checksums
  sbyg_require_https "$url" || return
  sbyg_require_https "$checksum_url" || return
  tmpdir=$(mktemp -d) || return
  candidate="$tmpdir/${url##*/}"
  checksums="$tmpdir/SHA256SUMS"
  if ! sbyg_download "$url" "$candidate" ||
     ! sbyg_download "$checksum_url" "$checksums" ||
     ! sbyg_verify_checksum "$candidate" "$checksums" ||
     ! sbyg_atomic_install "$candidate" "$destination" "$mode"; then
    rm -rf -- "$tmpdir"
    return 1
  fi
  rm -rf -- "$tmpdir"
}

sbyg_with_lock() {
  local lock_path=${1-}
  local lock_parent
  shift || return 2
  [ -n "$lock_path" ] && [ "$#" -gt 0 ] || return 2
  lock_parent=${lock_path%/*}
  [ "$lock_parent" != "$lock_path" ] || lock_parent=.
  mkdir -p "$lock_parent" || return
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 9 || exit
      "$@"
    ) 9>"$lock_path"
    return
  fi

  local lock_dir="${lock_path}.d" attempt=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 300 ] || {
      printf 'timed out waiting for lock: %s\n' "$lock_path" >&2
      return 1
    }
    sleep 0.1
  done
  "$@"
  local status=$?
  rmdir "$lock_dir"
  return "$status"
}
