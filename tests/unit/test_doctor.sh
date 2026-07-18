#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin" "$tmpdir/state"

cat > "$tmpdir/core" <<'EOF'
#!/usr/bin/env bash
case ${1-} in
  version) echo 'sing-box version 1.14.0' ;;
  check) exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmpdir/core"
printf '%s\n' '{"token":"must-not-leak","inbounds":[]}' > "$tmpdir/config.json"

cat > "$tmpdir/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case ${1-} in
  is-active) exit 0 ;;
  restart) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$tmpdir/bin/systemctl"

PATH="$tmpdir/bin:$PATH" \
SBYG_CONFIG="$tmpdir/config.json" \
SBYG_CORE="$tmpdir/core" \
SBYG_TRANSACTION_STATE="$tmpdir/state" \
SBYG_LIB_DIR="$repo_root/lib" \
  bash "$repo_root/scripts/sb-doctor.sh" > "$tmpdir/output"

grep -Fx 'core_version=1.14.0' "$tmpdir/output"
grep -Fx 'config=ok' "$tmpdir/output"
grep -Fx 'service=active' "$tmpdir/output"
grep -Fx 'transaction=none' "$tmpdir/output"
if grep -F 'must-not-leak' "$tmpdir/output"; then
  echo 'doctor leaked configuration data' >&2
  exit 1
fi

echo 'redacted doctor: PASS'
