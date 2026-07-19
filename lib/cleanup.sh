#!/usr/bin/env bash

sbyg_realpath_existing_or_missing() {
  local path=${1-}
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$path" 2>/dev/null || realpath -- "$path" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
  else
    printf 'realpath support is required for safe cleanup\n' >&2
    return 1
  fi
}

sbyg_literal_path() {
  local path=${1-} parent base resolved_parent
  case $path in
    /*) ;;
    *) return 2 ;;
  esac
  case "/$path/" in
    */../*|*/./*) return 2 ;;
  esac
  parent=${path%/*}
  base=${path##*/}
  [ -n "$base" ] && [ "$base" != . ] && [ "$base" != .. ] || return 2
  [ -n "$parent" ] || parent=/
  resolved_parent=$(sbyg_realpath_existing_or_missing "$parent") || return
  printf '%s/%s\n' "${resolved_parent%/}" "$base"
}

sbyg_path_within() {
  local candidate=${1-} root=${2-}
  local literal_candidate resolved_candidate resolved_root
  [ -n "$candidate" ] && [ -n "$root" ] || return 2
  case $root in
    /*) ;;
    *) return 2 ;;
  esac
  resolved_root=$(sbyg_realpath_existing_or_missing "$root") || return
  [ "$resolved_root" != / ] || return 2
  literal_candidate=$(sbyg_literal_path "$candidate") || return
  [ "$literal_candidate" != "$resolved_root" ] || return 2
  resolved_candidate=$(sbyg_realpath_existing_or_missing "$candidate") || return
  case "$literal_candidate" in
    "$resolved_root"/*) ;;
    *) return 2 ;;
  esac
  case "$resolved_candidate" in
    "$resolved_root"/*) return 0 ;;
    *) return 2 ;;
  esac
}

sbyg_manifest_add() {
  local manifest=${1-} root=${2-} path=${3-} literal_path parent
  sbyg_path_within "$manifest" "$root" || return 2
  sbyg_path_within "$path" "$root" || return 2
  literal_path=$(sbyg_literal_path "$path") || return
  parent=${manifest%/*}
  umask 077
  mkdir -p "$parent" || return
  [ ! -e "$manifest" ] || [ -f "$manifest" ] && [ ! -L "$manifest" ] || return 2
  if ! grep -Fx -- "$literal_path" "$manifest" 2>/dev/null; then
    printf '%s\n' "$literal_path" >> "$manifest" || return
  fi
  chmod 600 "$manifest"
}

sbyg_cleanup_manifest() {
  local manifest=${1-} root=${2-} path
  local -a paths=()
  [ -f "$manifest" ] || return 0
  [ ! -L "$manifest" ] || return 2

  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    sbyg_path_within "$path" "$root" || {
      printf 'unsafe manifest path refused: %s\n' "$path" >&2
      return 2
    }
    paths+=("$path")
  done < "$manifest"

  for path in "${paths[@]}"; do
    if [ "${SBYG_CLEANUP_DRY_RUN:-0}" = 1 ]; then
      printf '%s\n' "$path"
    elif [ -L "$path" ] || [ -f "$path" ]; then
      rm -f -- "$path" || return 1
    elif [ -d "$path" ]; then
      rm -rf -- "$path" || return 1
    fi
  done
}

sbyg_pid_manifest_add() {
  local manifest=${1-} pid=${2-} marker=${3-} parent
  case $pid in ''|*[!0-9]*) return 2 ;; esac
  [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ] || return 2
  case $marker in ''|*$'\t'*|*$'\n'*|*$'\r'*) return 2 ;; esac
  parent=${manifest%/*}
  umask 077
  mkdir -p "$parent" || return
  printf '%s\t%s\n' "$pid" "$marker" >> "$manifest" || return
  chmod 600 "$manifest"
}

sbyg_kill_recorded_pids() {
  local manifest=${1-} pid marker command_line status=0
  [ -f "$manifest" ] || return 0
  while IFS=$'\t' read -r pid marker; do
    case $pid in ''|*[!0-9]*) status=1; continue ;; esac
    [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ] || { status=1; continue; }
    command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case $command_line in
      *"$marker"*) kill -TERM "$pid" 2>/dev/null || true ;;
      *) status=1 ;;
    esac
  done < "$manifest"
  return "$status"
}

sbyg_kill_recorded_marker() {
  local manifest=${1-} wanted=${2-} pid marker command_line temporary status=0
  [ -f "$manifest" ] || return 0
  [ ! -L "$manifest" ] || return 2
  case $wanted in ''|*$'\t'*|*$'\n'*|*$'\r'*) return 2 ;; esac
  temporary="${manifest}.sbyg.$$"
  umask 077
  : > "$temporary" || return
  while IFS=$'\t' read -r pid marker; do
    if [ "$marker" != "$wanted" ]; then
      printf '%s\t%s\n' "$pid" "$marker" >> "$temporary" || {
        rm -f -- "$temporary"
        return 1
      }
      continue
    fi
    case $pid in ''|*[!0-9]*) status=1; continue ;; esac
    [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ] || { status=1; continue; }
    command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case $command_line in
      *"$marker"*) kill -TERM "$pid" 2>/dev/null || true ;;
      *) status=1 ;;
    esac
  done < "$manifest"
  chmod 600 "$temporary" || { rm -f -- "$temporary"; return 1; }
  mv -f -- "$temporary" "$manifest" || return
  return "$status"
}
