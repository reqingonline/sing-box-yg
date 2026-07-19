#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

shell_files=(sb.sh serv00.sh serv00keep.sh kp.sh)
while IFS= read -r -d '' file; do shell_files+=("$file"); done \
  < <(find lib scripts -type f -name '*.sh' -print0 | sort -z)
security_files=(sb.sh serv00.sh serv00keep.sh kp.sh)
while IFS= read -r -d '' file; do security_files+=("$file"); done \
  < <(find lib scripts -type f -name '*.sh' ! -name 'release-checks.sh' -print0 | sort -z)

bash -n "${shell_files[@]}"
command -v shellcheck >/dev/null 2>&1 || {
  echo 'release checks require shellcheck' >&2
  exit 1
}
shellcheck -x -S error "${shell_files[@]}"

if grep -RInE 'curl[^[:cntrl:]]*[[:space:]]-[A-Za-z]*k([[:space:]]|$)|wget[^[:cntrl:]]*--no-check-certificate' \
  "${security_files[@]}"; then
  echo 'TLS verification bypass found' >&2
  exit 1
fi
if grep -RInE '(curl|wget)[^[:cntrl:]]*http://' "${security_files[@]}" | \
  grep -Ev '127\.0\.0\.1|localhost'; then
  echo 'insecure public download URL found' >&2
  exit 1
fi
if grep -RInE 'chmod[[:space:]]+(666|777|a\+rw|a\+rwx)' "${security_files[@]}"; then
  echo 'broad write permissions found' >&2
  exit 1
fi
if grep -RInE 'bash[[:space:]]*<\([[:space:]]*(curl|wget)' "${security_files[@]}"; then
  echo 'direct execution of a downloaded script found' >&2
  exit 1
fi

while IFS= read -r untracked; do
  case $untracked in
    *.sh|*.bash|*.zip|*.tar|*.tar.gz|*.tgz|*.bin)
      echo "untracked executable/archive candidate: $untracked" >&2
      exit 1
      ;;
  esac
done < <(git ls-files --others --exclude-standard)

while IFS= read -r archive; do
  [ -z "$archive" ] && continue
  basename=${archive##*/}
  grep -RqsE "^[0-9A-Fa-f]{64}[[:space:]]+\*?${basename//./\\.}$" . --include='SHA256SUMS' || {
    echo "tracked archive lacks a SHA256SUMS entry: $archive" >&2
    exit 1
  }
done < <(git ls-files '*.zip' '*.tar' '*.tar.gz' '*.tgz')

for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -e "$workflow" ] || continue
  grep -q '^permissions:' "$workflow" || {
    echo "workflow lacks explicit permissions: $workflow" >&2
    exit 1
  }
  if [ "${workflow##*/}" != release.yml ] && grep -q 'contents:[[:space:]]*write' "$workflow"; then
    echo "non-release workflow requests contents: write: $workflow" >&2
    exit 1
  fi
  while IFS= read -r use_line; do
    printf '%s\n' "$use_line" | grep -Eq 'uses:[[:space:]]+[^[:space:]@]+@[0-9a-f]{40}([[:space:]]|$)' || {
      echo "workflow action is not pinned by full commit: $workflow: $use_line" >&2
      exit 1
    }
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$workflow" || true)
done

bash tests/run.sh
git diff --check
echo 'release preflight: PASS'
