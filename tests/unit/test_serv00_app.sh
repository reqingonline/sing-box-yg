#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
fake_home="$tmpdir/home"
workdir="$fake_home/domains/tester.serv00.net/logs"
server_pid=
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$workdir"
printf '%s\n' 'test-access-token-1234' > "$workdir/UUID.txt"
printf '%s\n' 'subscription-secret' > "$workdir/list.txt"
cat > "$fake_home/serv00keep.sh" <<'EOF'
#!/usr/bin/env bash
printf 'run\n' >> "$HOME/keep-runs"
EOF
cat > "$fake_home/webport.sh" <<'EOF'
#!/usr/bin/env bash
printf 'ports\n' >> "$HOME/port-runs"
EOF
chmod 700 "$fake_home/serv00keep.sh" "$fake_home/webport.sh"

HOME="$fake_home" SBYG_SERV00_USER=tester SBYG_APP_PORT=0 SBYG_DISABLE_AUTO_KEEP=1 \
  node "$repo_root/app.js" > "$tmpdir/app.log" 2>&1 &
server_pid=$!

port=
for _ in $(seq 1 50); do
  port=$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "$tmpdir/app.log" | tail -n 1)
  [ -z "$port" ] || break
  sleep 0.1
done
[ -n "$port" ] || { cat "$tmpdir/app.log" >&2; exit 1; }

status=$(curl --silent --output "$tmpdir/unauthorized" --write-out '%{http_code}' \
  "http://127.0.0.1:$port/jc/wrong-token")
[ "$status" = 404 ]
grep -Fx '未找到资源' "$tmpdir/unauthorized"

curl --fail --silent "http://127.0.0.1:$port/list/test-access-token-1234" \
  > "$tmpdir/subscription"
grep -Fx 'subscription-secret' "$tmpdir/subscription"

status=$(curl --silent --output "$tmpdir/up" --write-out '%{http_code}' \
  "http://127.0.0.1:$port/up/test-access-token-1234")
[ "$status" = 202 ]
for _ in $(seq 1 20); do
  [ -s "$fake_home/keep-runs" ] && break
  sleep 0.1
done
grep -Fx 'run' "$fake_home/keep-runs"

curl --fail --silent "http://127.0.0.1:$port/jc/test-access-token-1234" > "$tmpdir/status"
jq -e '.config_present == false and .subscription_present == true' "$tmpdir/status" >/dev/null
if grep -E 'ps aux|--token|subscription-secret' "$tmpdir/status"; then
  echo 'Serv00 status endpoint exposed process arguments or secrets' >&2
  exit 1
fi

echo 'Serv00 authenticated app: PASS'
