#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
log="$tmpdir/firewall.log"

iptables() {
  printf 'iptables %s\n' "$*" >> "$log"
  case " $* " in *' -C '*) return 1 ;; esac
  return 0
}
ip6tables() {
  printf 'ip6tables %s\n' "$*" >> "$log"
  case " $* " in *' -C '*) return 1 ;; esac
  return 0
}

source "$repo_root/lib/firewall.sh"
sbyg_fw_add_udp_dnat '20000:20100' 18444

grep -F -- 'iptables -w -t nat -N SBYG_PREROUTING' "$log"
grep -F -- 'iptables -w -t nat -A PREROUTING -m comment --comment sing-box-yg -j SBYG_PREROUTING' "$log"
grep -F -- 'iptables -w -t nat -A SBYG_PREROUTING -p udp --dport 20000:20100' "$log"
grep -F -- 'ip6tables -w -t nat -A SBYG_PREROUTING -p udp --dport 20000:20100' "$log"

if grep -E -- '-F (PREROUTING|INPUT)|-P (INPUT|FORWARD|OUTPUT) ACCEPT|-t mangle -F|ufw disable' "$log"; then
  echo 'global firewall state was mutated' >&2
  exit 1
fi

if grep -nE 'ufw disable|iptables -P (INPUT|FORWARD|OUTPUT) ACCEPT|iptables -t mangle -F|iptables -t nat -F PREROUTING' "$repo_root/sb.sh"; then
  echo 'legacy global firewall mutation remains in sb.sh' >&2
  exit 1
fi

echo 'owned firewall chain: PASS'
