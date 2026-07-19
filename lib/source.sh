#!/usr/bin/env bash

# Repository and release identity. Environment overrides exist for isolated tests.
SBYG_REPOSITORY=${SBYG_REPOSITORY:-reqingonline/sing-box-yg}
SBYG_CHANNEL=${SBYG_CHANNEL:-stable}
SBYG_GITHUB_API=${SBYG_GITHUB_API:-https://api.github.com}

sbyg_current_ref() {
  local installed_ref_file source_root
  if [ -n "${SBYG_REF:-}" ]; then
    printf '%s\n' "$SBYG_REF"
    return
  fi
  source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd) || source_root=
  for installed_ref_file in \
    "${SBYG_INSTALL_ROOT:-/usr/local/lib/sing-box-yg}/release-ref" \
    "$source_root/release-ref" \
    /etc/s-box/release-ref; do
    [ -r "$installed_ref_file" ] || continue
    IFS= read -r SBYG_INSTALLED_REF < "$installed_ref_file"
    sbyg_validate_ref "$SBYG_INSTALLED_REF" || return
    printf '%s\n' "$SBYG_INSTALLED_REF"
    return
  done
  printf 'main\n'
}

sbyg_project_file_url() {
  sbyg_raw_url "$(sbyg_current_ref)" "$1"
}

sbyg_validate_ref() {
  case ${1-} in
    ''|*[!A-Za-z0-9._/-]*|*..*|/*|*/)
      printf 'invalid repository ref: %s\n' "${1-}" >&2
      return 2
      ;;
  esac
}

sbyg_validate_asset_path() {
  case ${1-} in
    ''|/*|*..*|*\\*|*$'\n'*|*$'\r'*)
      printf 'invalid repository path: %s\n' "${1-}" >&2
      return 2
      ;;
  esac
}

sbyg_raw_url() {
  local ref=${1-} path=${2-}
  sbyg_validate_ref "$ref" || return
  sbyg_validate_asset_path "$path" || return
  printf 'https://raw.githubusercontent.com/%s/%s/%s\n' \
    "$SBYG_REPOSITORY" "$ref" "$path"
}

sbyg_release_api_url() {
  local version=${1:-latest}
  if [ "$version" = latest ]; then
    printf '%s/repos/%s/releases/latest\n' "$SBYG_GITHUB_API" "$SBYG_REPOSITORY"
    return
  fi
  sbyg_validate_ref "$version" || return
  printf '%s/repos/%s/releases/tags/%s\n' \
    "$SBYG_GITHUB_API" "$SBYG_REPOSITORY" "$version"
}

sbyg_release_asset_url() {
  local version=${1-} asset=${2-}
  sbyg_validate_ref "$version" || return
  sbyg_validate_asset_path "$asset" || return
  printf 'https://github.com/%s/releases/download/%s/%s\n' \
    "$SBYG_REPOSITORY" "$version" "$asset"
}

sbyg_version_triplet() {
  local version=${1#v}
  version=${version%%+*}
  version=${version%%-*}
  case $version in
    *[!0-9.]*|*.*.*.*|.*|*.|*..*) return 2 ;;
  esac
  local major minor patch extra
  IFS=. read -r major minor patch extra <<EOF
$version
EOF
  [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ] && [ -z "${extra-}" ] || return 2
  printf '%d %d %d\n' "$major" "$minor" "$patch"
}

sbyg_version_at_least() {
  local current_major current_minor current_patch
  local wanted_major wanted_minor wanted_patch
  read -r current_major current_minor current_patch <<EOF
$(sbyg_version_triplet "$1")
EOF
  read -r wanted_major wanted_minor wanted_patch <<EOF
$(sbyg_version_triplet "$2")
EOF
  [ "$current_major" -gt "$wanted_major" ] || {
    [ "$current_major" -eq "$wanted_major" ] &&
      { [ "$current_minor" -gt "$wanted_minor" ] || {
        [ "$current_minor" -eq "$wanted_minor" ] &&
          [ "$current_patch" -ge "$wanted_patch" ]
      }; }
  }
}
