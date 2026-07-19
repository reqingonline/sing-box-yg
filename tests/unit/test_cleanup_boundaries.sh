#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fake_home="$tmpdir/home"
manifest="$fake_home/.sbyg/assets.v1"

mkdir -p "$fake_home/.ssh" "$fake_home/.sbyg" "$fake_home/project/cache" "$tmpdir/outside"
printf 'ssh-key\n' > "$fake_home/.ssh/authorized_keys"
printf 'personal\n' > "$fake_home/personal.txt"
printf 'managed\n' > "$fake_home/project/cache/data"
printf 'managed-file\n' > "$fake_home/project.conf"
printf 'outside\n' > "$tmpdir/outside/keep"

source "$repo_root/lib/cleanup.sh"
sbyg_manifest_add "$manifest" "$fake_home" "$fake_home/project"
sbyg_manifest_add "$manifest" "$fake_home" "$fake_home/project.conf"
sbyg_cleanup_manifest "$manifest" "$fake_home"

test ! -e "$fake_home/project"
test ! -e "$fake_home/project.conf"
grep -Fx ssh-key "$fake_home/.ssh/authorized_keys"
grep -Fx personal "$fake_home/personal.txt"
grep -Fx outside "$tmpdir/outside/keep"

for unsafe in '' / "$fake_home" "$fake_home/.." "$fake_home/../outside"; do
  if sbyg_path_within "$unsafe" "$fake_home"; then
    echo "unsafe cleanup path accepted: $unsafe" >&2
    exit 1
  fi
done

case $(uname -s) in
  MINGW*|MSYS*) ;;
  *)
    if ln -s "$tmpdir/outside" "$fake_home/escape" 2>/dev/null; then
      if sbyg_path_within "$fake_home/escape" "$fake_home"; then
        echo 'escaping symlink was accepted' >&2
        exit 1
      fi
    fi
    ;;
esac

if grep -nE 'find ~ .*rm -rf|killall -9 -u|find ~ -type [fd] -exec (chmod|rm)' \
  "$repo_root/serv00.sh" "$repo_root/serv00keep.sh"; then
  echo 'broad Serv00 cleanup remains' >&2
  exit 1
fi

pid_manifest="$fake_home/.sbyg/pids.v1"
kill_log="$tmpdir/kill.log"
printf '123\towned-core\n456\towned-tunnel\n' > "$pid_manifest"
ps() {
  case $2 in
    123) printf '%s\n' "$fake_home/owned-core run" ;;
    456) printf '%s\n' "$fake_home/owned-tunnel run" ;;
  esac
}
kill() { printf '%s\n' "$*" >> "$kill_log"; }
sbyg_kill_recorded_marker "$pid_manifest" owned-core
grep -Fx -- '-TERM 123' "$kill_log"
grep -Fx $'456\towned-tunnel' "$pid_manifest"
if grep -F owned-core "$pid_manifest"; then
  echo 'stopped PID remained in the project manifest' >&2
  exit 1
fi

echo 'bounded cleanup: PASS'
