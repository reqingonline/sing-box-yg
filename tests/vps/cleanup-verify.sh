#!/usr/bin/env bash
set -euo pipefail
sentinel=${SBYG_ACCEPTANCE_SENTINEL:?set SBYG_ACCEPTANCE_SENTINEL}
ufw_before=${SBYG_ACCEPTANCE_UFW_BEFORE:-active}
ssh_before=${SBYG_ACCEPTANCE_SSH_RULES:-1}
grep -Fx keep "$sentinel"
iptables -w -S SBYG_UNRELATED_SENTINEL >/dev/null
! iptables -w -t nat -S SBYG_PREROUTING >/dev/null 2>&1
test "$(ufw status | awk 'NR==1{print $2}')" = "$ufw_before"
test "$(ufw status | grep -cE '(^|[[:space:]])22(/tcp)?([[:space:]]|$)' || true)" = "$ssh_before"
! systemctl is-active --quiet sbyg-acceptance.service
echo 'cleanup preservation: PASS'
