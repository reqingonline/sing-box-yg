#!/usr/bin/env bash
set -euo pipefail

umask 077
log=${SING_BOX_YG_HEALTH_LOG:-/var/log/sing-box-yg-health.log}
doctor=${SING_BOX_YG_DOCTOR:-/usr/local/lib/sing-box-yg/sb-doctor.sh}
install -d -m 700 "$(dirname "$log")"
printf 'checked_at=%s\n' "$(date --iso-8601=seconds)" >> "$log"
"$doctor" >> "$log"
