#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." 2>/dev/null && pwd)
lib_dir=${SBYG_LIB_DIR:-/usr/local/lib/sing-box-yg/lib}
for library in download secrets transaction firewall service; do
  if [ -r "$lib_dir/$library.sh" ]; then
    . "$lib_dir/$library.sh"
  elif [ -r "$repo_root/lib/$library.sh" ]; then
    . "$repo_root/lib/$library.sh"
  fi
done

config=${SBYG_CONFIG:-/etc/s-box/sb.json}
core=${SBYG_CORE:-/etc/s-box/sing-box}
state=${SBYG_TRANSACTION_STATE:-/etc/s-box/.transaction}
repair=0
[ "${1-}" = --repair ] && repair=1

doctor_value() {
  printf '%s' "${1-}" | tr '\r\n' '  ' | sed -E \
    's/((private_token|access_token|token|password|uuid)=)[^[:space:]&]+/\1[redacted]/Ig'
}

doctor_line() {
  printf '%s=%s\n' "$1" "$(doctor_value "${2-}")"
}

os_name=unknown
if [ -r /etc/os-release ]; then
  os_name=$(awk -F= '$1 == "PRETTY_NAME" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release)
fi
doctor_line os "$os_name"
doctor_line architecture "$(uname -m 2>/dev/null || printf unknown)"

core_version=missing
if [ -x "$core" ]; then
  core_version=$("$core" version 2>/dev/null | awk '/version/ {print $NF; exit}')
  [ -n "$core_version" ] || core_version=unknown
fi
doctor_line core_version "$core_version"

config_status=missing
config_hash=missing
if [ -f "$config" ] && [ -x "$core" ]; then
  config_hash=$(sha256sum "$config" 2>/dev/null | awk '{print $1}')
  if "$core" check -c "$config" >/dev/null 2>&1; then
    config_status=ok
  else
    config_status=invalid
  fi
fi
doctor_line config "$config_status"
doctor_line config_sha256 "$config_hash"

if declare -F sbyg_service_active >/dev/null 2>&1 && sbyg_service_active; then
  service_status=active
else
  service_status=inactive
fi
doctor_line service "$service_status"

ports=none
listener_status=unknown
if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
  ports=$(jq -r '[.inbounds[]? | .listen_port // empty] | unique | join(",")' "$config" 2>/dev/null || printf invalid)
  [ -n "$ports" ] || ports=none
  if declare -F sbyg_expected_ports_listening >/dev/null 2>&1 &&
     SBYG_HEALTH_ATTEMPTS=1 SBYG_HEALTH_DELAY=0 sbyg_expected_ports_listening "$config" >/dev/null 2>&1; then
    listener_status=ready
  else
    listener_status=not-ready
  fi
fi
doctor_line listener_ports "$ports"
doctor_line listeners "$listener_status"

firewall_status=absent
if command -v iptables >/dev/null 2>&1 &&
   iptables -w -t nat -S "${SBYG_NAT_CHAIN:-SBYG_PREROUTING}" >/dev/null 2>&1; then
  firewall_status=owned-chain-present
fi
doctor_line firewall "$firewall_status"

transaction_status=none
[ -f "$state/committed" ] && transaction_status=committed
[ -f "$state/rollback-failed" ] && transaction_status=rollback-failed
doctor_line transaction "$transaction_status"

certificate_count=0
if [ -f "$config" ] && command -v jq >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
  while IFS= read -r certificate; do
    [ -f "$certificate" ] || continue
    certificate_count=$((certificate_count + 1))
    expiry=$(openssl x509 -in "$certificate" -noout -enddate 2>/dev/null | cut -d= -f2-)
    doctor_line "certificate_${certificate_count}_expiry" "${expiry:-unreadable}"
  done <<EOF
$(jq -r '.inbounds[]?.tls.certificate_path // empty' "$config" 2>/dev/null | sort -u)
EOF
fi
doctor_line certificate_count "$certificate_count"

repair_status=not-requested
if [ "$repair" -eq 1 ]; then
  if [ "$config_status" = ok ]; then
    if [ "$service_status" = active ]; then
      repair_status=healthy-no-action
    elif declare -F sbyg_service_restart >/dev/null 2>&1 &&
         sbyg_service_restart >/dev/null 2>&1 && sbyg_service_active; then
      repair_status=restarted
      service_status=active
    else
      repair_status=restart-failed
    fi
  elif [ -f "$state/config.previous" ] && [ -f "$state/core.previous" ] &&
       declare -F sbyg_transaction_rollback >/dev/null 2>&1 &&
       sbyg_transaction_rollback "$state" "$config" "$core" >/dev/null 2>&1; then
    repair_status=rolled-back
    config_status=ok
    service_status=active
  else
    repair_status=invalid-no-safe-rollback
  fi
fi
doctor_line repair "$repair_status"

[ "$config_status" = ok ] && [ "$service_status" = active ]
