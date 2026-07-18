#!/usr/bin/env bash

sbyg_config_profile() {
  local version=${1-}
  if sbyg_version_at_least "$version" v1.14.0; then
    printf '1.14\n'
  elif sbyg_version_at_least "$version" v1.12.0; then
    printf '1.12\n'
  elif sbyg_version_at_least "$version" v1.11.0; then
    printf '1.11\n'
  else
    printf '1.10\n'
  fi
}

sbyg_config_template_name() {
  case $(sbyg_config_profile "$1") in
    1.10) printf 'sb10.json\n' ;;
    *) printf 'sb11.json\n' ;;
  esac
}

sbyg_config_prepare() {
  local source=${1-} destination=${2-} version=${3-}
  local profile parent temporary mode
  [ -f "$source" ] && [ -n "$destination" ] || return 2
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required for configuration compatibility\n' >&2
    return 2
  }
  profile=$(sbyg_config_profile "$version") || return
  parent=${destination%/*}
  [ "$parent" != "$destination" ] || parent=.
  mkdir -p "$parent" || return
  temporary="$parent/.${destination##*/}.sbyg.$$"

  case $profile in
    1.10|1.11)
      jq '.' "$source" > "$temporary"
      ;;
    1.12)
      jq '
        .dns = (.dns // {}) |
        .dns.servers = (if (.dns.servers // [] | length) == 0 then
          [{"type":"local","tag":"local"}]
        else .dns.servers end) |
        .route = (.route // {}) |
        .route.default_domain_resolver = (.route.default_domain_resolver // "local") |
        .experimental = (.experimental // {}) |
        .experimental.cache_file = ((.experimental.cache_file // {}) +
          {"enabled":true,"path":"/etc/s-box/cache.db"})
      ' "$source" > "$temporary"
      ;;
    1.14)
      jq '
        .dns = (.dns // {}) |
        .dns.servers = (if (.dns.servers // [] | length) == 0 then
          [{"type":"local","tag":"local"}]
        else .dns.servers end) |
        .http_clients = (if (.http_clients // [] | length) == 0 then
          [{"tag":"direct","engine":"go"}]
        else .http_clients end) |
        .route = (.route // {}) |
        .route.default_domain_resolver = (.route.default_domain_resolver // "local") |
        .route.default_http_client = (.route.default_http_client // "direct") |
        .route.rule_set = ((.route.rule_set // []) | map(
          if .type == "remote" then
            .http_client = (.http_client // .download_detour // "direct") | del(.download_detour)
          else . end
        )) |
        .experimental = (.experimental // {}) |
        .experimental.cache_file = ((.experimental.cache_file // {}) +
          {"enabled":true,"path":"/etc/s-box/cache.db","store_dns":true})
      ' "$source" > "$temporary"
      ;;
  esac || {
    rm -f "$temporary"
    return 1
  }

  mode=600
  chmod "$mode" "$temporary" || { rm -f "$temporary"; return 1; }
  mv -f -- "$temporary" "$destination"
}
