#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_env() {
  unset HERDR_ENV
  hd_run ls
  assert_eq 1 "$HD_RC" "hd ls exit"
  assert_contains "$HD_OUT" "not inside Herdr" "hd ls stderr"
}

run_case env_outside_herdr case_env

case_foreign_pane() {
  local other
  sleep 60 & other=$!
  mkdir -p "$FAKE_DIR/panes/w9:p1"
  printf '%s' "$other" > "$FAKE_DIR/panes/w9:p1/shell-pid"
  HERDR_PANE_ID=w9:p1 HERDR_WORKSPACE_ID=w9 hd_run ls
  kill "$other"
  assert_eq 1 "$HD_RC" "hd ls from a foreign pane"
  assert_contains "$HD_OUT" "not this process's pane" "hd ls stderr"
}

run_case env_foreign_pane case_foreign_pane
