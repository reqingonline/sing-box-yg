#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fragment="$tmpdir/functions.sh"
log="$tmpdir/assets.log"

sed -n '/^download_to_temp(){/,/^inssb(){/p' "$repo_root/sb.sh" | sed '$d' > "$fragment"
source "$fragment"

install_github_latest_asset() {
  local repository=$1 asset=$2 destination=$3 mode=$4
  printf '%s %s %s\n' "$repository" "$asset" "$mode" >> "$log"
  mkdir -p "${destination%/*}"
  printf '%s\n' "$asset" > "$destination"
  chmod "$mode" "$destination"
}

GEO_DATABASE_DIR="$tmpdir/databases"
mkdir -p "$GEO_DATABASE_DIR"
install_geo_databases
grep -Fx 'MetaCubeX/meta-rules-dat geoip.db 644' "$log"
grep -Fx 'MetaCubeX/meta-rules-dat geosite.db 644' "$log"
grep -Fx geoip.db "$GEO_DATABASE_DIR/geoip.db"
grep -Fx geosite.db "$GEO_DATABASE_DIR/geosite.db"
case $(uname -s) in
  MINGW*|MSYS*) ;;
  *) test "$(stat -c %a "$GEO_DATABASE_DIR/geoip.db")" = 644 ;;
esac
