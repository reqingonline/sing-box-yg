#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
documents=(README.md docs/SECURITY.md docs/MIGRATION.md docs/RELEASE.md)
for document in "${documents[@]}"; do
  test -f "$repo_root/$document"
done

while IFS= read -r target; do
  case $target in
    http://*|https://*|mailto:*|'#'*) continue ;;
  esac
  target=${target%%#*}
  test -e "$repo_root/$target" || {
    echo "missing repository-relative documentation target: $target" >&2
    exit 1
  }
done < <(grep -hoE '\]\(([^)]+)\)' "$repo_root/README.md" | sed -E 's/^\]\((.*)\)$/\1/')

if grep -nE 'bash[[:space:]]*<\((curl|wget)|(^|[[:space:]])(curl|wget)[^`]*\|[[:space:]]*(sudo[[:space:]]+)?bash' \
  "$repo_root/README.md" "$repo_root/docs/"*.md; then
  echo 'documentation recommends direct remote script execution' >&2
  exit 1
fi

echo 'documentation contract: PASS'
