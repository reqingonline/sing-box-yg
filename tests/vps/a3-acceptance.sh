#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: a3-acceptance.sh baseline [output]
       a3-acceptance.sh check [output]
       a3-acceptance.sh backup [backup-dir]
       a3-acceptance.sh rollback [backup-dir]

This helper is intentionally fail-closed.  It never deletes project data,
flushes a firewall, or edits SSH configuration.  The rollback mode only
restores files from an explicit backup directory under /tmp/sbyg-a3.
EOF
}

die() { printf 'a3: %s\n' "$*" >&2; exit 2; }

require_root() { [ "$(id -u)" -eq 0 ] || die 'must run as root'; }

core=/etc/s-box/sing-box
config=/etc/s-box/sb.json
unit=sing-box.service
health_timer=sing-box-yg-health.timer
state_dir=/tmp/sbyg-a3

private_hash() {
  [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf 'absent\n'
}

backup_host() {
  local output=${1:-$state_dir/backup-$(date -u +%Y%m%dT%H%M%SZ)}
  case "$output" in
    "$state_dir"/*) ;;
    *) die 'backup must be an explicit child of /tmp/sbyg-a3' ;;
  esac
  [ "$output" != "$state_dir" ] || die 'backup path must not be the state directory itself'
  [ ! -e "$output" ] || die "backup path already exists: $output"
  [ -f "$config" ] || die "missing configuration: $config"

  mkdir -p "$output"
  chmod 700 "$output"
  install -m 600 "$config" "$output/sb.json"

  # Capture only the files that A3 may need to restore; do not copy the whole
  # /etc/s-box tree or any unrelated system directories.
  for source in \
    /etc/systemd/system/sing-box.service \
    /etc/systemd/system/sing-box-yg-health.service \
    /etc/systemd/system/sing-box-yg-health.timer \
    /usr/local/lib/sing-box-yg/release-ref; do
    if [ -f "$source" ]; then
      install -m 600 "$source" "$output/$(basename "$source")"
    fi
  done

  (
    cd "$output"
    sha256sum -- * > SHA256SUMS
  )
  chmod 600 "$output/SHA256SUMS"
  printf 'backup=%s\n' "$output"
}

write_baseline() {
  local output=${1:-$state_dir/baseline.redacted}
  mkdir -p "${output%/*}"
  umask 077
  {
    printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'os='; . /etc/os-release; printf '%s-%s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}"
    printf 'kernel=%s\n' "$(uname -r)"
    printf 'architecture=%s\n' "$(uname -m)"
    printf 'memory_kib=%s\n' "$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    printf 'root_free_kib=%s\n' "$(df -Pk / | awk 'NR==2{print $4}')"
    printf 'core_present=%s\n' "$([ -x "$core" ] && echo true || echo false)"
    printf 'config_present=%s\n' "$([ -f "$config" ] && echo true || echo false)"
    printf 'core_sha256=%s\n' "$(private_hash "$core")"
    printf 'config_sha256=%s\n' "$(private_hash "$config")"
    printf 'core_version='; "$core" version 2>/dev/null | awk '/version/{print $NF; exit}' || true; printf '\n'
    printf 'service_active=%s\n' "$(systemctl is-active "$unit" 2>/dev/null || true)"
    printf 'service_enabled=%s\n' "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    printf 'health_timer_active=%s\n' "$(systemctl is-active "$health_timer" 2>/dev/null || true)"
    printf 'health_timer_enabled=%s\n' "$(systemctl is-enabled "$health_timer" 2>/dev/null || true)"
    printf 'listening_socket_count=%s\n' "$(ss -H -lntup 2>/dev/null | wc -l)"
    printf 'sbox_file_modes=\n'
    find /etc/s-box -maxdepth 1 -type f -printf '%f %m %s\n' 2>/dev/null | sort || true
    printf 'ufw_status='; ufw status 2>/dev/null | awk 'NR==1{print $2}' || printf 'unavailable'; printf '\n'
    printf 'nft_table_count=%s\n' "$(nft list tables 2>/dev/null | wc -l)"
  } > "$output"
  chmod 600 "$output"
  printf '%s\n' "$output"
}

check_host() {
  local output=${1:-$state_dir/check.redacted}
  mkdir -p "${output%/*}"
  umask 077
  [ -x "$core" ] || die "missing executable: $core"
  [ -f "$config" ] || die "missing configuration: $config"
  "$core" check -c "$config"
  systemctl is-active --quiet "$unit"
  "$core" version | awk '/version/{print "core_version=" $NF; exit}' > "$output"
  printf 'config_sha256=%s\n' "$(private_hash "$config")" >> "$output"
  printf 'service_active=true\n' >> "$output"
  printf 'listen_summary=\n' >> "$output"
  ss -H -lntup 2>/dev/null | awk '{print $1, $4}' | sort -u >> "$output" || true
  chmod 600 "$output"
  printf '%s\n' "$output"
}

rollback_backup() {
  local backup=${1-}
  case "$backup" in
    "$state_dir"/*) ;;
    *) die 'backup must be an explicit child of /tmp/sbyg-a3' ;;
  esac
  [ -d "$backup" ] || die "backup directory not found: $backup"
  [ -f "$backup/sb.json" ] || die 'backup is missing sb.json'
  if [ -f "$backup/SHA256SUMS" ]; then
    (cd "$backup" && sha256sum -c SHA256SUMS >/dev/null) || die 'backup manifest verification failed'
  fi
  install -m 600 "$backup/sb.json" "$config"
  reloaded=0
  for unit_file in sing-box.service sing-box-yg-health.service sing-box-yg-health.timer; do
    if [ -f "$backup/$unit_file" ]; then
      install -m 644 "$backup/$unit_file" "/etc/systemd/system/$unit_file"
      reloaded=1
    fi
  done
  if [ "$reloaded" -eq 1 ]; then
    systemctl daemon-reload
  fi
  "$core" check -c "$config"
  systemctl restart "$unit"
  systemctl is-active --quiet "$unit"
  printf 'rollback=PASS\nconfig_sha256=%s\n' "$(private_hash "$config")"
}

require_root
mode=${1-}
case "$mode" in
  baseline) write_baseline "${2:-$state_dir/baseline.redacted}" ;;
  check) check_host "${2:-$state_dir/check.redacted}" ;;
  backup) backup_host "${2:-}" ;;
  rollback) rollback_backup "${2-}" ;;
  *) usage >&2; exit 2 ;;
esac
