#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_env() {
  unset HERDR_ENV
  hd_run ls
  assert_eq 1 "$HD_RC" "hd ls exit"
  assert_contains "$HD_OUT" "not inside Herdr" "hd ls stderr"
}

run_case env_outside_herdr case_env
