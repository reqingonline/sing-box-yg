#!/usr/bin/env bash
set -euo pipefail
output=${1:-/tmp/sbyg-baseline.redacted}
umask 077
{
  echo "os=$(source /etc/os-release; printf '%s' "$ID-$VERSION_ID")"
  echo "kernel=$(uname -r)"
  echo "architecture=$(uname -m)"
  echo "memory_kib=$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  echo "root_free_kib=$(df -Pk / | awk 'NR==2{print $4}')"
  echo "listening_socket_count=$(ss -H -lntup 2>/dev/null | wc -l)"
  echo "ufw=$(ufw status 2>/dev/null | awk 'NR==1{print $2}' || echo unavailable)"
  echo "ssh_rule_count=$(ufw status 2>/dev/null | grep -cE '(^|[[:space:]])22(/tcp)?([[:space:]]|$)' || true)"
  if [ -f /etc/s-box/sb.json ]; then echo "config_sha256=$(sha256sum /etc/s-box/sb.json | awk '{print $1}')"; else echo 'config_sha256=absent'; fi
} > "$output"
chmod 600 "$output"
echo "$output"
