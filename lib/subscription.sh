#!/usr/bin/env bash

sbyg_subscription_validate_token() {
  local token=${1-}
  [ "${#token}" -ge 24 ] && [ "${#token}" -le 128 ] || return 2
  case $token in
    *[!A-Za-z0-9_-]*) return 2 ;;
  esac
}

sbyg_subscription_token() {
  if declare -F sbyg_generate_token >/dev/null 2>&1; then
    sbyg_generate_token
  elif command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    printf 'secure token generator is unavailable\n' >&2
    return 1
  fi
}

sbyg_subscription_validate_port() {
  local port=${1-}
  case $port in
    ''|*[!0-9]*) return 2 ;;
  esac
  [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]
}

sbyg_subscription_prepare_root() {
  local root=${1-} token=${2-}
  [ -n "$root" ] && [ "$root" != / ] || return 2
  sbyg_subscription_validate_token "$token" || {
    printf 'invalid subscription token\n' >&2
    return 2
  }
  umask 077
  mkdir -p "$root/$token" || return
  chmod 700 "$root" "$root/$token"
}

sbyg_subscription_remove_token_root() {
  local root=${1-} token=${2-}
  [ -n "$root" ] && [ "$root" != / ] || return 2
  sbyg_subscription_validate_token "$token" || return 2
  [ -d "$root/$token" ] || return 0
  rm -rf -- "$root/$token"
}

sbyg_subscription_start_loopback() {
  local root=${1-} port=${2-} log=${3:-/dev/null} httpd parent
  [ -d "$root" ] || {
    printf 'subscription root does not exist: %s\n' "$root" >&2
    return 2
  }
  sbyg_subscription_validate_port "$port" || {
    printf 'invalid subscription port: %s\n' "$port" >&2
    return 2
  }
  httpd=${SBYG_BUSYBOX_BIN:-}
  if [ -z "$httpd" ]; then
    httpd=$(command -v busybox-extras 2>/dev/null || command -v busybox 2>/dev/null) || {
      printf 'BusyBox HTTP server is unavailable\n' >&2
      return 1
    }
  fi
  if [ "$log" != /dev/null ]; then
    parent=${log%/*}
    [ "$parent" != "$log" ] || parent=.
    mkdir -p "$parent" || return
    : > "$log"
    chmod 600 "$log" 2>/dev/null || true
  fi
  "$httpd" httpd -f -p "127.0.0.1:$port" -h "$root" >"$log" 2>&1 &
  printf '%s\n' "$!"
}

sbyg_subscription_url_redacted() {
  local port=${1-} token=${2-}
  sbyg_subscription_validate_port "$port" || return 2
  sbyg_subscription_validate_token "$token" || return 2
  if declare -F sbyg_redact >/dev/null 2>&1; then
    token=$(sbyg_redact "$token")
  else
    token='[redacted]'
  fi
  printf 'http://127.0.0.1:%s/%s/\n' "$port" "$token"
}

sbyg_subscription_public_url() {
  local base=${1-} token=${2-} file=${3-}
  case $base in
    https://*) ;;
    *) printf 'public subscriptions require HTTPS\n' >&2; return 2 ;;
  esac
  sbyg_subscription_validate_token "$token" || return 2
  case $file in
    clmi.yaml|sbox.json|jhsub.txt) ;;
    *) return 2 ;;
  esac
  printf '%s/%s/%s\n' "${base%/}" "$token" "$file"
}
