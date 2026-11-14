#!/usr/bin/env bash
# A published skill must not carry the author's paths, a fixed install location,
# or a hardwired model: the same directory serves every project and install.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

grep_skill() {
  grep -rn --exclude-dir=tests --exclude-dir=.git -- "$1" "$ROOT" 2>/dev/null || true
}

case_no_author_paths() {
  local hits
  hits="$(grep_skill '/\(home\|Users\)/[^/[:space:]]\+/')"
  [[ -z "$hits" ]] || t_fail "author path or repo URL in the skill: $hits"

  hits="$(grep_skill '~/.claude/skills')"
  [[ -z "$hits" ]] || t_fail "fixed driver path in the skill: $hits"
}

case_no_hardwired_model() {
  local hits
  hits="$(grep -nE 'opencode-go|deepseek|qwen|anthropic/|openai/' "$HD" || true)"
  [[ -z "$hits" ]] || t_fail "hardwired provider or model default in hd: $hits"

  hits="$(grep -n 'DEFAULT_MODEL="[^$]' "$HD" || true)"
  [[ -z "$hits" ]] || t_fail "DEFAULT_MODEL is not read from the environment: $hits"
}

case_driver_is_executable() {
  [[ -x "$HD" ]] || t_fail "hd is not executable"
  [[ -x "$ROOT/tests/fake/herdr" ]] || t_fail "the fake herdr is not executable"
}

run_case hygiene_no_author_paths case_no_author_paths
run_case hygiene_no_hardwired_model case_no_hardwired_model
run_case hygiene_driver_is_executable case_driver_is_executable
