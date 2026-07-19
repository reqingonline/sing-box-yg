#!/usr/bin/env bash
set -euo pipefail

repository=${SBYG_REPOSITORY:-reqingonline/sing-box-yg}
github_api=${SBYG_GITHUB_API:-https://api.github.com}
release_base=${SBYG_RELEASE_BASE:-https://github.com/$repository/releases/download}
channel=stable
requested_version=
prefix=${SBYG_PREFIX:-/usr/local/lib/sing-box-yg}
dry_run=false
upgrade=false

usage() {
  cat <<'EOF'
Usage: install.sh [--channel stable|main] [--version vX.Y.Z]
                  [--prefix PATH] [--dry-run] [--upgrade]

Stable is the default and requires a release archive covered by SHA256SUMS.
The main channel is development-only and must be selected explicitly.
EOF
}

die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --channel)
      [ "$#" -ge 2 ] || die '--channel requires a value'
      channel=$2
      shift 2
      ;;
    --version)
      [ "$#" -ge 2 ] || die '--version requires a value'
      requested_version=$2
      shift 2
      ;;
    --prefix)
      [ "$#" -ge 2 ] || die '--prefix requires a value'
      prefix=$2
      shift 2
      ;;
    --dry-run) dry_run=true; shift ;;
    --upgrade) upgrade=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case $channel in
  stable|main) ;;
  *) die "unsupported channel: $channel" ;;
esac
[ -z "$requested_version" ] || channel=stable
case $repository in
  */*) ;;
  *) die 'repository must be OWNER/REPO' ;;
esac
case $prefix in
  /*) ;;
  *) die 'prefix must be an absolute path' ;;
esac
[ "$prefix" != / ] || die 'prefix cannot be /'

architecture=${SBYG_TEST_ARCH:-$(uname -m)}
case $architecture in
  x86_64|amd64|aarch64|arm64|armv7l|armv7) ;;
  *) die "unsupported architecture: $architecture" ;;
esac

for command_name in curl tar awk mktemp find; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is missing: $command_name"
done
if command -v sha256sum >/dev/null 2>&1; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  die 'sha256sum or shasum is required'
fi

allow_url() {
  case $1 in
    https://*) return 0 ;;
    http://127.0.0.1:*|http://localhost:*)
      [ "${SBYG_TEST_ALLOW_HTTP:-0}" = 1 ]
      ;;
    *) return 1 ;;
  esac
}

fetch() {
  local url=$1 destination=$2
  allow_url "$url" || die "refusing non-HTTPS URL: $url"
  if [ "${SBYG_TEST_ALLOW_HTTP:-0}" = 1 ]; then
    curl --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 180 "$url" -o "$destination"
  else
    curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
      --connect-timeout 15 --max-time 180 "$url" -o "$destination"
  fi
}

workdir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-yg-install.XXXXXX")
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT HUP INT TERM

tag=
archive_name=
archive_url=
checksum_url=
if [ "$channel" = stable ]; then
  if [ -n "$requested_version" ]; then
    tag=$requested_version
  else
    release_json="$workdir/release.json"
    fetch "$github_api/repos/$repository/releases/latest" "$release_json"
    tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | head -n 1)
  fi
  case $tag in
    v[0-9A-Za-z]*) ;;
    *) die "invalid or missing release tag: $tag" ;;
  esac
  case $tag in
    *[!0-9A-Za-z._-]*) die "invalid release tag: $tag" ;;
  esac
  archive_name="sing-box-yg-$tag.tar.gz"
  archive_url="$release_base/$tag/$archive_name"
  checksum_url="$release_base/$tag/SHA256SUMS"
else
  [ -z "$requested_version" ] || die '--version cannot be combined with --channel main'
  commit_json="$workdir/commit.json"
  fetch "$github_api/repos/$repository/commits/main" "$commit_json"
  tag=$(sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]*\)".*/\1/p' "$commit_json" | head -n 1)
  case $tag in
    ????????????????????????????????????????) ;;
    *) die 'unable to resolve the main commit exactly once' ;;
  esac
  archive_name="sing-box-yg-$tag.tar.gz"
  archive_url="https://github.com/$repository/archive/$tag.tar.gz"
fi

printf 'Repository: %s\n' "$repository"
printf 'Selected ref: %s (%s)\n' "$tag" "$channel"
if $dry_run; then
  printf 'Would install into: %s\n' "$prefix"
  exit 0
fi
if $upgrade && [ ! -d "$prefix" ]; then
  die "cannot upgrade missing prefix: $prefix"
fi

archive="$workdir/$archive_name"
fetch "$archive_url" "$archive"
actual_digest=$(sha256_file "$archive")
if [ "$channel" = stable ]; then
  checksums="$workdir/SHA256SUMS"
  fetch "$checksum_url" "$checksums"
  expected_digest=$(awk -v file="$archive_name" '$2 == file || $2 == "*" file {print $1; exit}' "$checksums")
  printf '%s\n' "$expected_digest" | grep -Eq '^[0-9A-Fa-f]{64}$' || \
    die "missing checksum entry for $archive_name"
  [ "${expected_digest,,}" = "${actual_digest,,}" ] || die "SHA-256 mismatch for $archive_name"
else
  printf 'WARNING: main is a development channel; digest is transport-derived only.\n' >&2
fi
printf 'Archive SHA-256: %s\n' "$actual_digest"

extract="$workdir/extract"
mkdir -p "$extract"
tar -xzf "$archive" -C "$extract"
root_count=$(find "$extract" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$root_count" = 1 ] || die 'release archive must contain exactly one root directory'
source_root=$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print | head -n 1)
for required in sb.sh lib/source.sh scripts/install.sh; do
  [ -f "$source_root/$required" ] || die "release is missing $required"
done
while IFS= read -r shell_file; do
  bash -n "$shell_file" || die "shell syntax check failed: ${shell_file#"$source_root/"}"
done < <(find "$source_root" -type f -name '*.sh' -print)

parent=${prefix%/*}
[ "$parent" != "$prefix" ] || parent=/
mkdir -p "$parent"
stage="$parent/.sing-box-yg.new.$$"
backup="$parent/.sing-box-yg.old.$$"
rm -rf "$stage" "$backup"
mkdir -p "$stage"
cp -a "$source_root"/. "$stage"/
printf '%s\n' "$tag" > "$stage/release-ref"
printf '%s\n' "$repository" > "$stage/repository"
printf '%s\n' "$actual_digest" > "$stage/release-digest"
chmod 755 "$stage/sb.sh" "$stage/scripts/install.sh"

wrapper_tmp=
if [ "$prefix" = /usr/local/lib/sing-box-yg ]; then
  wrapper_tmp="$workdir/sb"
  cat > "$wrapper_tmp" <<'EOF'
#!/bin/sh
export SBYG_INSTALL_ROOT=/usr/local/lib/sing-box-yg
export SBYG_LIB_DIR=/usr/local/lib/sing-box-yg/lib
exec /usr/local/lib/sing-box-yg/sb.sh "$@"
EOF
  chmod 755 "$wrapper_tmp"
  [ -d /usr/bin ] && [ -w /usr/bin ] || die '/usr/bin is not writable'
fi

rollback=false
if [ -e "$prefix" ]; then
  mv -- "$prefix" "$backup"
  rollback=true
fi
if ! mv -- "$stage" "$prefix"; then
  $rollback && mv -- "$backup" "$prefix"
  die 'atomic installation failed; previous version restored'
fi
if [ -n "$wrapper_tmp" ]; then
  wrapper_candidate="/usr/bin/.sb.sing-box-yg.$$"
  if ! install -m 755 "$wrapper_tmp" "$wrapper_candidate" || \
     ! mv -f -- "$wrapper_candidate" /usr/bin/sb; then
    rm -f "$wrapper_candidate"
    rm -rf "$prefix"
    $rollback && mv -- "$backup" "$prefix"
    die 'command wrapper installation failed; previous version restored'
  fi
fi
rm -rf "$backup"

printf 'Installed %s at %s\n' "$tag" "$prefix"
