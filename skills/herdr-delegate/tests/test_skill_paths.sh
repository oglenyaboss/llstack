#!/usr/bin/env bash
# The driver must work from wherever the skill is installed: roles and
# the envelope resolve next to hd, never from a fixed home directory.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_skill_dir_copied() {
  local copy="$CASE_TMP/elsewhere/skills/herdr-delegate"
  mkdir -p "$(dirname "$copy")"
  cp -a "$ROOT" "$copy"

  local out rc
  set +e
  out="$(cd "$CASE_TMP/work" && "$copy/hd" spawn w1 worker 2>&1)"
  rc=$?
  set -e
  assert_eq 0 "$rc" "hd from a copy"
  assert_contains "$out" "spawned w1 role=worker" "spawn line"

  local dir
  dir="$(single_agent_dir)"
  assert_file_contains "$dir/start.args" "--append-system-prompt $copy/roles/worker.md" "role prompt path"
  assert_file_contains "$dir/start.args" "--append-system-prompt $copy/roles/_envelope.md" "envelope path"
  assert_not_contains "$(cat "$dir/start.args")" "$HOME/.claude" "no fixed home driver path"
}

case_symlinked_skill_dir() {
  local link="$CASE_TMP/linked-herdr-delegate"
  ln -s "$ROOT" "$link"

  local out rc
  set +e
  out="$(cd "$CASE_TMP/work" && "$link/hd" spawn w1 scout 2>&1)"
  rc=$?
  set -e
  assert_eq 0 "$rc" "hd through a symlink"
  assert_contains "$out" "spawned w1 role=scout" "spawn line"
  local dir
  dir="$(single_agent_dir)"
  assert_file_contains "$dir/start.args" "roles/scout.md" "role prompt path"
}

run_case skill_dir_copied case_skill_dir_copied
run_case skill_dir_through_symlink case_symlinked_skill_dir
