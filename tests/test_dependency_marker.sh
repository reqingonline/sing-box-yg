#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

grep -Fx 'dependency_marker=/etc/s-box/.sbyg-dependencies' "$repo_root/sb.sh"
grep -Fx 'if [ ! -f "$dependency_marker" ]; then' "$repo_root/sb.sh"
grep -F 'touch "$dependency_marker" ||' "$repo_root/sb.sh"
grep -Fx 'apk add "$inspackage"' "$repo_root/sb.sh"
if grep -Eq 'apt(-get)? install[^[:cntrl:]]*iptables-persistent|yum update|dnf update' "$repo_root/sb.sh"; then
  echo 'dependency bootstrap performs firewall-breaking or whole-system updates' >&2
  exit 1
fi
grep -F 'dependency_install_status' "$repo_root/sb.sh"
grep -F 'dependency marker was not written' "$repo_root/sb.sh"
if grep -Fqx 'if [ ! -f sbyg_update ]; then' "$repo_root/sb.sh"; then exit 1; fi
if grep -Fqx 'touch sbyg_update' "$repo_root/sb.sh"; then exit 1; fi
