#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

spawn_w1() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_calls_nonempty
}

case_prompt_timeout() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: still_working"
}

case_blocked_status() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
printf 'blocked' > "$FAKE_DIR/agents/$1/status"
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: blocked_ui"
  assert_contains "$HD_OUT" "SCREEN TAIL"
}

case_provider_error_retry() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  turn "$2" "partial" error overloaded
else
  turn "$2" "fixed
STATUS: done"
fi
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: done"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
  local dir
  dir="$(single_agent_dir)"
  assert_file_contains "$dir/last-prompt" "provider error (overloaded)"
}

case_provider_error_twice() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "partial" error overloaded
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: provider_error"
  assert_contains "$HD_OUT" "agent=pi model=prov/m1"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

run_file() {
  local file
  file="$(find "$XDG_CACHE_HOME/herdr-delegate" -name "$1" -print -quit)"
  [[ -n "$file" ]] || t_fail "no run dir entry $1"
  printf '%s\n' "$file"
}

fallback_spawn() {
  printf 'prov m1\nprov m2\nprov m3\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"fallback":[{"model":"prov/m2"}]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
}

fallback_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if (( $3 < 3 )); then
  turn "$2" "partial" error overloaded
else
  turn "$2" "fixed
STATUS: done"
fi
EOF
}

fallback_ask() {
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "--- fallback: prov/m1 → prov/m2: overloaded" "fallback line"
  assert_contains "$HD_OUT" "STATUS: done" "replacement envelope"
}

case_fallback_switch() {
  fallback_spawn
  fallback_hook
  fallback_ask
  local dir
  dir="$(single_agent_dir)"
  assert_file_contains "$dir/start.args" "--model prov/m2" "replacement model"
  assert_file_contains "$dir/last-prompt" "Do the work." "resent brief"
  assert_file_contains "$dir/last-prompt" "OUTPUT_FILE:" "resent output file"
  assert_file_contains "$dir/last-prompt" "A previous attempt at this brief ended on a provider error" "resent warning"
  assert_eq 3 "$(prompt_calls)" "prompt count"
}

case_fallback_ls_and_journal() {
  fallback_spawn
  fallback_hook
  fallback_ask
  hd_run ls
  assert_eq 0 "$HD_RC" "hd ls"
  local line
  line="$(grep '^w1 ' <<<"$HD_OUT")"
  [[ "$line" == *" model=prov/m2" ]] || t_fail "ls line does not end with the replacement model: [$line]"
  local entry
  entry="$(tail -n 1 "$XDG_CACHE_HOME/herdr-delegate/journal.jsonl")"
  assert_jq '.models == ["prov/m1","prov/m2"]' "$entry" "journal models"
}

case_fallback_chain_exhausted() {
  printf 'prov m1\nprov m2\nprov m3\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"fallback":[{"model":"prov/m2"},{"model":"prov/m3"}]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "partial" error overloaded
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_eq 2 "$(grep -c -- '--- fallback:' <<<"$HD_OUT")" "fallback lines"
  assert_contains "$HD_OUT" "STATUS: provider_error"
  assert_contains "$HD_OUT" "models tried: prov/m1 → prov/m2 → prov/m3" "models tried"
  assert_eq 6 "$(prompt_calls)" "prompt count"
}

case_fallback_absent_exhausted() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "partial" error overloaded
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: provider_error"
  assert_contains "$HD_OUT" "agent=pi model=prov/m1"
  assert_contains "$HD_OUT" "models tried: prov/m1"
  assert_not_contains "$HD_OUT" "--- fallback" "no fallback without a list"
  assert_eq 2 "$(prompt_calls)" "prompt count"
}

case_fallback_resume() {
  fallback_spawn
  fallback_hook
  fallback_ask
  hd_run stop w1
  assert_eq 0 "$HD_RC" "hd stop w1"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "hd resume w1"
  assert_file_contains "$(single_agent_dir)/start.args" "--model prov/m2" "replacement model on resume"
}

case_fallback_used_up() {
  fallback_spawn
  fallback_hook
  fallback_ask
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "partial" error overloaded
EOF
  hd_run ask w1 'Do the work again.'
  assert_eq 0 "$HD_RC" "second ask exit"
  assert_not_contains "$HD_OUT" "--- fallback" "used up list"
  assert_contains "$HD_OUT" "STATUS: provider_error"
  assert_contains "$HD_OUT" "models tried: prov/m2" "models tried"
}

case_fallback_keeps_out() {
  fallback_spawn
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if (( $3 == 1 )); then
  sed -n 's/^OUTPUT_FILE: //p' "$FAKE_DIR/agents/$1/last-prompt" | tail -n 1 > "$FAKE_DIR/out-before"
fi
if (( $3 < 3 )); then
  turn "$2" "partial" error overloaded
else
  turn "$2" "fixed
STATUS: done"
fi
EOF
  fallback_ask
  local out_before
  out_before="$(<"$FAKE_DIR/out-before")"
  assert_eq "$out_before" "$(cat "$(run_file w1.out)")" ".out after the switch"
  assert_eq "$out_before" "$(sed -n 's/^OUTPUT_FILE: //p' "$(single_agent_dir)/last-prompt" | tail -n 1)" "resent OUTPUT_FILE"
}

run_case errors_prompt_timeout case_prompt_timeout
run_case errors_blocked_status case_blocked_status
run_case errors_provider_error_retry case_provider_error_retry
run_case errors_provider_error_twice case_provider_error_twice
run_case errors_fallback_switch case_fallback_switch
run_case errors_fallback_ls_and_journal case_fallback_ls_and_journal
run_case errors_fallback_chain_exhausted case_fallback_chain_exhausted
run_case errors_fallback_absent_exhausted case_fallback_absent_exhausted
run_case errors_fallback_resume case_fallback_resume
run_case errors_fallback_used_up case_fallback_used_up
run_case errors_fallback_keeps_out case_fallback_keeps_out
