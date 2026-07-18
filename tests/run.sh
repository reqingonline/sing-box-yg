#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for test_file in "$repo_root"/tests/test_*.sh; do
  bash "$test_file"
done

if [ -d "$repo_root/tests/unit" ]; then
  while IFS= read -r -d '' test_file; do
    bash "$test_file"
  done < <(find "$repo_root/tests/unit" -maxdepth 1 -type f -name 'test_*.sh' -print0 | sort -z)
fi

if [ -d "$repo_root/tests/integration" ]; then
  bash "$repo_root/tests/integration/install-smoke.sh"
fi
