#!/usr/bin/env bash
# Runs every case against the fake herdr in tests/fake/. ROOT is the skill
# directory, so this works from a copy of the skill without a repo checkout.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
passed=0
failed=0

for file in "$ROOT"/tests/test_*.sh; do
  [[ -e "$file" ]] || continue
  output="$(bash "$file" 2>&1)"
  rc=$?
  while IFS= read -r line; do
    case "$line" in
      "ok "*)
        passed=$((passed + 1))
        printf '%s\n' "$line"
        ;;
      "FAIL "*)
        failed=$((failed + 1))
        printf '%s\n' "$line"
        ;;
      *)
        printf '%s\n' "$line" >&2
        ;;
    esac
  done <<< "$output"
  if (( rc != 0 )); then
    failed=$((failed + 1))
    printf 'FAIL %s: test file exited %s\n' "$(basename "$file")" "$rc"
  fi
done

printf '%s passed, %s failed\n' "$passed" "$failed"
(( failed == 0 ))
