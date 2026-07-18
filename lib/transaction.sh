#!/usr/bin/env bash

sbyg_transaction_copy() {
  local source=${1-} destination=${2-} mode=${3-}
  [ -f "$source" ] || {
    printf 'transaction source is missing: %s\n' "$source" >&2
    return 2
  }
  if declare -F sbyg_atomic_install >/dev/null 2>&1; then
    sbyg_atomic_install "$source" "$destination" "$mode"
  else
    local parent temporary
    parent=${destination%/*}
    [ "$parent" != "$destination" ] || parent=.
    mkdir -p "$parent" || return
    temporary="$parent/.${destination##*/}.sbyg.$$"
    umask 077
    cp -- "$source" "$temporary" || {
      rm -f "$temporary"
      return 1
    }
    chmod "$mode" "$temporary" || {
      rm -f "$temporary"
      return 1
    }
    mv -f -- "$temporary" "$destination"
  fi
}

sbyg_transaction_begin() {
  local state=${1-} config=${2-} core=${3-}
  [ -n "$state" ] && [ "$state" != / ] || return 2
  [ -f "$config" ] && [ -f "$core" ] || return 2
  umask 077
  mkdir -p "$state" || return
  chmod 700 "$state" || return
  sbyg_transaction_copy "$config" "$state/config.previous" 600 || return
  sbyg_transaction_copy "$core" "$state/core.previous" 755 || return
  printf '%s\n' "$config" > "$state/config.path"
  printf '%s\n' "$core" > "$state/core.path"
  chmod 600 "$state/config.path" "$state/core.path"
  rm -f "$state/committed" "$state/rollback-failed"
}

sbyg_validate_config() {
  local core=${1-} config=${2-}
  [ -x "$core" ] && [ -f "$config" ] || return 2
  "$core" check -c "$config"
}

sbyg_service_restart() {
  if command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box restart
  else
    systemctl restart sing-box
  fi
}

sbyg_service_active() {
  if command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box status >/dev/null 2>&1
  else
    systemctl is-active --quiet sing-box
  fi
}

sbyg_expected_ports_listening() {
  local config=${1-} port attempts=${SBYG_HEALTH_ATTEMPTS:-10}
  local delay=${SBYG_HEALTH_DELAY:-1} output all_ready
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required for listener verification\n' >&2
    return 2
  }
  command -v ss >/dev/null 2>&1 || {
    printf 'ss is required for listener verification\n' >&2
    return 2
  }
  while [ "$attempts" -gt 0 ]; do
    output=$(ss -H -lntup 2>/dev/null || true)
    all_ready=1
    while IFS= read -r port; do
      [ -n "$port" ] || continue
      if ! printf '%s\n' "$output" | grep -Eq "[:.]${port}[[:space:]]"; then
        all_ready=0
        break
      fi
    done <<EOF
$(jq -r '.inbounds[]? | .listen_port // empty' "$config")
EOF
    [ "$all_ready" -eq 1 ] && return 0
    attempts=$((attempts - 1))
    [ "$attempts" -gt 0 ] && sleep "$delay"
  done
  printf 'one or more expected ports did not become ready\n' >&2
  return 1
}

sbyg_transaction_rollback() {
  local state=${1-} config=${2-} core=${3-}
  local status=0
  [ -f "$state/config.previous" ] && [ -f "$state/core.previous" ] || return 2
  sbyg_transaction_copy "$state/config.previous" "$config" 600 || status=1
  sbyg_transaction_copy "$state/core.previous" "$core" 755 || status=1
  if [ "$status" -eq 0 ]; then
    sbyg_validate_config "$core" "$config" || status=1
  fi
  if [ "$status" -eq 0 ]; then
    sbyg_service_restart && sbyg_service_active || status=1
  fi
  if [ "$status" -ne 0 ]; then
    : > "$state/rollback-failed"
    return 1
  fi
  rm -f "$state/committed" "$state/rollback-failed"
}

sbyg_transaction_apply() {
  local state=${1-} config=${2-} core=${3-}
  [ -f "$state/config.previous" ] && [ -f "$state/core.previous" ] || return 2
  if ! sbyg_validate_config "$core" "$config"; then
    sbyg_transaction_rollback "$state" "$config" "$core" >/dev/null 2>&1 || return 2
    return 1
  fi
  if ! sbyg_service_restart ||
     ! sbyg_service_active ||
     ! sbyg_expected_ports_listening "$config"; then
    sbyg_transaction_rollback "$state" "$config" "$core" >/dev/null 2>&1 || return 2
    return 1
  fi
  umask 077
  : > "$state/committed"
  chmod 600 "$state/committed"
}
