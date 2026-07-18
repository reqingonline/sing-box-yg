#!/usr/bin/env bash

sbyg_redact() {
  local value=${1-} length=${#1}
  if [ "$length" -lt 12 ]; then
    printf '[redacted]\n'
    return
  fi
  printf '%s...%s\n' "${value:0:4}" "${value:length-4:4}"
}

sbyg_secret_dir() {
  local directory=${1-}
  [ -n "$directory" ] && [ "$directory" != / ] || return 2
  umask 077
  mkdir -p "$directory" || return
  chmod 700 "$directory"
}

sbyg_write_secret() {
  local destination=${1-} value=${2-} parent temporary
  [ -n "$destination" ] && [ "$destination" != / ] || return 2
  parent=${destination%/*}
  [ "$parent" != "$destination" ] || parent=.
  sbyg_secret_dir "$parent" || return
  temporary="$parent/.${destination##*/}.sbyg.$$"
  umask 077
  if ! printf '%s\n' "$value" > "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  chmod 600 "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$destination"
}

sbyg_read_secret() {
  local path=${1-}
  [ -f "$path" ] || return 1
  IFS= read -r REPLY < "$path" || [ -n "${REPLY-}" ]
  printf '%s\n' "${REPLY-}"
}

sbyg_generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
    return
  fi
  if [ -r /dev/urandom ]; then
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
    printf '\n'
    return
  fi
  printf 'no cryptographically secure random source is available\n' >&2
  return 1
}

sbyg_assert_private_file() {
  local path=${1-} mode
  [ -f "$path" ] || return 1
  mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null) || return
  case $mode in
    600|400) return 0 ;;
  esac
  printf 'secret file has unsafe mode %s: %s\n' "$mode" "$path" >&2
  return 1
}
