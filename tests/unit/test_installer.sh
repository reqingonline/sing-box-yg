#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
installer="$repo_root/scripts/install.sh"
test -x "$installer" || {
  echo 'verified installer is missing or not executable' >&2
  exit 1
}

for command_name in curl tar sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "installer test: SKIP ($command_name unavailable)"
    exit 0
  }
done
if command -v python3 >/dev/null 2>&1; then
  fixture_server=python
elif command -v node >/dev/null 2>&1; then
  fixture_server=node
else
  echo 'installer test: SKIP (python3/node unavailable)'
  exit 0
fi

tmpdir=$(mktemp -d)
server_pid=
trap 'test -z "$server_pid" || kill "$server_pid" 2>/dev/null || true; rm -rf "$tmpdir"' EXIT
fixture="$tmpdir/http"
repository=reqingonline/sing-box-yg

make_release() {
  local tag=$1 marker=$2 release_root asset_dir asset archive
  release_root="$tmpdir/source/sing-box-yg-$tag"
  asset="sing-box-yg-$tag.tar.gz"
  asset_dir="$fixture/releases/download/$tag"
  rm -rf "$release_root"
  mkdir -p "$release_root/lib" "$release_root/scripts" "$asset_dir"
  printf '#!/usr/bin/env bash\necho %q\n' "$marker" > "$release_root/sb.sh"
  cp "$repo_root/lib/source.sh" "$release_root/lib/source.sh"
  cp "$installer" "$release_root/scripts/install.sh"
  printf '%s\n' "$marker" > "$release_root/VERSION"
  chmod +x "$release_root/sb.sh" "$release_root/scripts/install.sh"
  archive="$asset_dir/$asset"
  tar -C "$tmpdir/source" -czf "$archive" "sing-box-yg-$tag"
  (cd "$asset_dir" && sha256sum "$asset" > SHA256SUMS)
}

make_release v1.2.2 older
make_release v1.2.3 latest
mkdir -p "$fixture/api/repos/$repository/releases"
printf '{"tag_name":"v1.2.3","prerelease":false,"draft":false}\n' \
  > "$fixture/api/repos/$repository/releases/latest"

port_file="$tmpdir/port"
if [ "$fixture_server" = python ]; then
python3 - "$fixture" "$port_file" <<'PY' &
import http.server
import os
import socketserver
import sys

root, port_file = sys.argv[1:]
os.chdir(root)
with socketserver.TCPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler) as server:
    with open(port_file, "w", encoding="ascii") as handle:
        handle.write(str(server.server_address[1]))
    server.serve_forever()
PY
else
node -e '
const fs = require("fs");
const http = require("http");
const path = require("path");
const root = path.resolve(process.argv[1]);
const portFile = process.argv[2];
const server = http.createServer((request, response) => {
  const requestPath = decodeURIComponent(request.url.split("?", 1)[0]);
  const candidate = path.resolve(root, `.${requestPath}`);
  if (!candidate.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403).end();
    return;
  }
  const stream = fs.createReadStream(candidate);
  stream.on("error", () => response.writeHead(404).end());
  stream.pipe(response);
});
server.listen(0, "127.0.0.1", () => {
  fs.writeFileSync(portFile, String(server.address().port));
});
' "$fixture" "$port_file" &
fi
server_pid=$!
for _ in $(seq 1 50); do
  test -s "$port_file" && break
  sleep 0.1
done
test -s "$port_file"
base_url="http://127.0.0.1:$(cat "$port_file")"

run_installer() {
  SBYG_TEST_ALLOW_HTTP=1 \
  SBYG_GITHUB_API="$base_url/api" \
  SBYG_RELEASE_BASE="$base_url/releases/download" \
    bash "$installer" "$@"
}

prefix="$tmpdir/install"
run_installer --prefix "$prefix"
test "$(cat "$prefix/VERSION")" = latest
test "$(cat "$prefix/release-ref")" = v1.2.3

run_installer --version v1.2.2 --prefix "$prefix"
test "$(cat "$prefix/VERSION")" = older
test "$(cat "$prefix/release-ref")" = v1.2.2

before=$(find "$prefix" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
printf '%064d  sing-box-yg-v1.2.3.tar.gz\n' 0 \
  > "$fixture/releases/download/v1.2.3/SHA256SUMS"
if run_installer --prefix "$prefix"; then
  echo 'installer accepted an invalid release digest' >&2
  exit 1
fi
after=$(find "$prefix" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
test "$before" = "$after"

unsupported="$tmpdir/unsupported"
if SBYG_TEST_ARCH=mips64 run_installer --prefix "$unsupported"; then
  echo 'installer accepted an unsupported architecture' >&2
  exit 1
fi
test ! -e "$unsupported"

echo 'verified installer: PASS'
