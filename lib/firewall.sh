#!/usr/bin/env bash

SBYG_NAT_CHAIN=${SBYG_NAT_CHAIN:-SBYG_PREROUTING}
SBYG_FIREWALL_COMMENT=${SBYG_FIREWALL_COMMENT:-sing-box-yg}

sbyg_fw_validate_port() {
  local value=${1-}
  case $value in
    ''|*[!0-9]*) return 2 ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

sbyg_fw_validate_port_spec() {
  local value=${1-} first last
  case $value in
    *:*)
      first=${value%%:*}
      last=${value##*:}
      [ "$first" != "$value" ] &&
        sbyg_fw_validate_port "$first" &&
        sbyg_fw_validate_port "$last" &&
        [ "$first" -le "$last" ]
      ;;
    *) sbyg_fw_validate_port "$value" ;;
  esac
}

sbyg_fw_ensure_chain_one() {
  local bin=${1-}
  "$bin" -w -t nat -N "$SBYG_NAT_CHAIN" 2>/dev/null || true
  "$bin" -w -t nat -C PREROUTING \
    -m comment --comment "$SBYG_FIREWALL_COMMENT" \
    -j "$SBYG_NAT_CHAIN" 2>/dev/null ||
    "$bin" -w -t nat -A PREROUTING \
      -m comment --comment "$SBYG_FIREWALL_COMMENT" \
      -j "$SBYG_NAT_CHAIN"
}

sbyg_fw_add_udp_dnat_one() {
  local bin=${1-} source_ports=${2-} target_port=${3-}
  sbyg_fw_ensure_chain_one "$bin" || return
  "$bin" -w -t nat -C "$SBYG_NAT_CHAIN" \
    -p udp --dport "$source_ports" \
    -m comment --comment "$SBYG_FIREWALL_COMMENT" \
    -j DNAT --to-destination ":$target_port" 2>/dev/null ||
    "$bin" -w -t nat -A "$SBYG_NAT_CHAIN" \
      -p udp --dport "$source_ports" \
      -m comment --comment "$SBYG_FIREWALL_COMMENT" \
      -j DNAT --to-destination ":$target_port"
}

sbyg_fw_remove_udp_dnat_one() {
  local bin=${1-} source_ports=${2-} target_port=${3-} attempts=0
  while "$bin" -w -t nat -C "$SBYG_NAT_CHAIN" \
    -p udp --dport "$source_ports" \
    -m comment --comment "$SBYG_FIREWALL_COMMENT" \
    -j DNAT --to-destination ":$target_port" 2>/dev/null; do
    "$bin" -w -t nat -D "$SBYG_NAT_CHAIN" \
      -p udp --dport "$source_ports" \
      -m comment --comment "$SBYG_FIREWALL_COMMENT" \
      -j DNAT --to-destination ":$target_port" || return 1
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || return 1
  done
}

sbyg_fw_remove_all_one() {
  local bin=${1-} attempts=0
  while "$bin" -w -t nat -C PREROUTING \
    -m comment --comment "$SBYG_FIREWALL_COMMENT" \
    -j "$SBYG_NAT_CHAIN" 2>/dev/null; do
    "$bin" -w -t nat -D PREROUTING \
      -m comment --comment "$SBYG_FIREWALL_COMMENT" \
      -j "$SBYG_NAT_CHAIN" || return 1
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || return 1
  done
  "$bin" -w -t nat -F "$SBYG_NAT_CHAIN" 2>/dev/null || true
  "$bin" -w -t nat -X "$SBYG_NAT_CHAIN" 2>/dev/null || true
}

sbyg_fw_each_available() {
  local callback=${1-}
  shift || return 2
  local found=0 bin status=0
  for bin in iptables ip6tables; do
    command -v "$bin" >/dev/null 2>&1 || continue
    found=1
    "$callback" "$bin" "$@" || status=1
  done
  [ "$found" -eq 1 ] || {
    printf 'iptables/ip6tables are unavailable\n' >&2
    return 2
  }
  return "$status"
}

sbyg_fw_add_udp_dnat() {
  local source_ports=${1-} target_port=${2-}
  sbyg_fw_validate_port_spec "$source_ports" || {
    printf 'invalid forwarding port specification: %s\n' "$source_ports" >&2
    return 2
  }
  sbyg_fw_validate_port "$target_port" || {
    printf 'invalid forwarding target port: %s\n' "$target_port" >&2
    return 2
  }
  sbyg_fw_each_available sbyg_fw_add_udp_dnat_one "$source_ports" "$target_port"
}

sbyg_fw_remove_udp_dnat() {
  local source_ports=${1-} target_port=${2-}
  sbyg_fw_validate_port_spec "$source_ports" || return 2
  sbyg_fw_validate_port "$target_port" || return 2
  sbyg_fw_each_available sbyg_fw_remove_udp_dnat_one "$source_ports" "$target_port"
}

sbyg_fw_remove_all() {
  sbyg_fw_each_available sbyg_fw_remove_all_one
}

sbyg_fw_list_udp_sources() {
  local target_port=${1-}
  sbyg_fw_validate_port "$target_port" || return 2
  command -v iptables >/dev/null 2>&1 || return 0
  iptables -w -t nat -S "$SBYG_NAT_CHAIN" 2>/dev/null |
    awk -v target=":$target_port" '
      $0 ~ /-p udp/ && $0 ~ /--dport/ && $0 ~ /--to-destination/ {
        for (i=1; i<=NF; i++) {
          if ($i == "--dport") source=$(i+1)
          if ($i == "--to-destination") destination=$(i+1)
        }
        if (destination == target) print source
      }'
}

sbyg_fw_persist() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  elif command -v service >/dev/null 2>&1 && service iptables status >/dev/null 2>&1; then
    service iptables save
  fi
}
