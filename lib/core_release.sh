#!/usr/bin/env bash

sbyg_sing_box_releases_json() {
  curl --fail --silent --show-error --location --retry 2 \
    --connect-timeout 10 --max-time 30 --proto '=https' \
    'https://api.github.com/repos/SagerNet/sing-box/releases?per_page=100'
}

sbyg_sing_box_release_channels() {
  local json=${1-} stable prerelease
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required for sing-box release selection\n' >&2
    return 2
  }
  if [ -z "$json" ]; then
    json=$(sbyg_sing_box_releases_json) || return 1
  fi
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json" || return 1
  stable=$(jq -r '[.[] | select(.draft != true and .prerelease != true) |
    .tag_name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty' <<<"$json")
  prerelease=$(jq -r '[.[] | select(.draft != true and .prerelease == true) |
    .tag_name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+-(alpha|beta|rc)\\.[0-9]+$"))][0] // empty' <<<"$json")
  stable=${stable#v}
  prerelease=${prerelease#v}
  printf 'stable=%s\nprerelease=%s\n' "$stable" "$prerelease"
}
