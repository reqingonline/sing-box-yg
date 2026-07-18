#!/usr/bin/env bash

sbyg_service_atomic_file() {
  local source=${1-} destination=${2-} mode=${3:-644} parent temporary
  parent=${destination%/*}
  [ "$parent" != "$destination" ] || parent=.
  mkdir -p "$parent" || return
  temporary="$parent/.${destination##*/}.sbyg.$$"
  cp -- "$source" "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  chmod "$mode" "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$destination"
}

sbyg_service_render_systemd() {
  local destination=${1-} core=${2-} config=${3-} writable=${4-}
  local temporary
  [ -n "$destination" ] && [ -n "$core" ] && [ -n "$config" ] && [ -n "$writable" ] || return 2
  temporary=$(mktemp) || return
  cat > "$temporary" <<EOF
[Unit]
Description=sing-box managed by sing-box-yg
Documentation=https://github.com/reqingonline/sing-box-yg
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
UMask=0077
WorkingDirectory=$writable
ExecStartPre=$core check -c $config
ExecStart=$core run -c $config
ExecReload=/bin/kill -HUP \$MAINPID
KillSignal=SIGINT
Restart=on-failure
RestartSec=10
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=$writable
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  sbyg_service_atomic_file "$temporary" "$destination" 644
  local status=$?
  rm -f "$temporary"
  return "$status"
}

sbyg_service_render_openrc() {
  local destination=${1-} core=${2-} config=${3-} writable=${4-}
  local temporary
  [ -n "$destination" ] && [ -n "$core" ] && [ -n "$config" ] && [ -n "$writable" ] || return 2
  temporary=$(mktemp) || return
  cat > "$temporary" <<EOF
#!/sbin/openrc-run
description="sing-box managed by sing-box-yg"
command="$core"
command_args="run -c $config"
command_user="root:root"
directory="$writable"
supervisor="supervise-daemon"
respawn_delay=10
respawn_max=0
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath -d -m 700 "$writable"
  "$core" check -c "$config"
}
EOF
  sbyg_service_atomic_file "$temporary" "$destination" 755
  local status=$?
  rm -f "$temporary"
  return "$status"
}

sbyg_service_render_health_timer() {
  local service_path=${1-} timer_path=${2-} doctor=${3-}
  local service_tmp timer_tmp status=0
  [ -n "$service_path" ] && [ -n "$timer_path" ] && [ -n "$doctor" ] || return 2
  service_tmp=$(mktemp) || return
  timer_tmp=$(mktemp) || { rm -f "$service_tmp"; return 1; }
  cat > "$service_tmp" <<EOF
[Unit]
Description=sing-box-yg validated health repair
After=network-online.target sing-box.service

[Service]
Type=oneshot
UMask=0077
ExecStart=$doctor --repair
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=read-only
ProtectSystem=strict
ReadWritePaths=/etc/s-box /var/lib/sing-box-yg /run
EOF
  cat > "$timer_tmp" <<EOF
[Unit]
Description=sing-box-yg health check every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
RandomizedDelaySec=30s
Persistent=true
Unit=sing-box-yg-health.service

[Install]
WantedBy=timers.target
EOF
  sbyg_service_atomic_file "$service_tmp" "$service_path" 644 || status=1
  [ "$status" -ne 0 ] || sbyg_service_atomic_file "$timer_tmp" "$timer_path" 644 || status=1
  rm -f "$service_tmp" "$timer_tmp"
  return "$status"
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

sbyg_service_logs() {
  local lines=${1:-100}
  if command -v rc-service >/dev/null 2>&1; then
    tail -n "$lines" /var/log/sing-box.log 2>/dev/null
  else
    journalctl -u sing-box.service -n "$lines" --no-pager -o cat
  fi
}
