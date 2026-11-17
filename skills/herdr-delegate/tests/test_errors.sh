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
  assert_contains "$HD_OUT" "agent=pi model=pi default"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

run_case errors_prompt_timeout case_prompt_timeout
run_case errors_blocked_status case_blocked_status
run_case errors_provider_error_retry case_provider_error_retry
run_case errors_provider_error_twice case_provider_error_twice
