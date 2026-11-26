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

assert_matches() {
  local text="$1" regex="$2" label="${3:-output}"
  [[ "$text" =~ $regex ]] || t_fail "$label: no match for [$regex] in [${text//$'\n'/ | }]"
}

assert_after_match() {
  local text="$1" first="$2" regex="$3" line found=0
  while IFS= read -r line; do
    if (( found )); then
      [[ "$line" =~ $regex ]] || t_fail "line after [$first] is [$line], expected match [$regex]"
      return 0
    fi
    [[ "$line" =~ $first ]] && found=1
  done <<< "$text"
  t_fail "missing line matching [$first]"
}

write_wait_hook() {
  cat > "$FAKE_DIR/on-wait"
  chmod +x "$FAKE_DIR/on-wait"
}

timeout_with_usage_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "partial"
printf '%s\n' "$(( $(date +%s) - 125 ))" > "$(find "$XDG_CACHE_HOME/herdr-delegate" -name w1.ask-start -print -quit)"
printf 'timeout waiting\n'
exit 1
EOF
}

case_still_working_ask_diagnostics() {
  spawn_w1
  timeout_with_usage_hook
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: still_working" "ask status"
  assert_matches "$HD_OUT" 'ctx=3k elapsed=2m[0-9]+s' "ask diagnostics"
  assert_after_match "$HD_OUT" '^STATUS: still_working$' '^ctx=3k elapsed=2m[0-9]+s$'
  assert_after_match "$HD_OUT" '^ctx=3k elapsed=2m[0-9]+s$' '^w1 has not finished; continue with: hd wait w1$'
}

case_still_working_wait_diagnostics() {
  spawn_w1
  timeout_with_usage_hook
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  write_wait_hook <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  hd_run wait w1
  assert_eq 0 "$HD_RC" "hd wait exit"
  assert_contains "$HD_OUT" "STATUS: still_working" "wait status"
  assert_matches "$HD_OUT" 'ctx=3k elapsed=2m[0-9]+s' "wait diagnostics"
  assert_after_match "$HD_OUT" '^STATUS: still_working$' '^ctx=3k elapsed=2m[0-9]+s$'
  assert_not_contains "$HD_OUT" "continue with: hd wait w1" "wait has no note"
}

case_still_working_empty_diagnostics() {
  spawn_w1
  rm -f "$XDG_CACHE_HOME"/herdr-delegate/*/w1.ask-start
  write_wait_hook <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  hd_run wait w1
  assert_eq 0 "$HD_RC" "hd wait exit"
  assert_contains "$HD_OUT" "STATUS: still_working" "wait status"
  assert_after_match "$HD_OUT" '^STATUS: still_working$' '^ctx= elapsed=$'
  assert_not_contains "$HD_OUT" "ctx=0" "no invented ctx"
  assert_not_contains "$HD_OUT" "elapsed=0s" "no invented elapsed"
}

case_still_working_skill_rule() {
  local line
  line="$(sed -n '50p' "$ROOT/SKILL.md")"
  assert_not_contains "$line" "growing context" "skill rule"
  assert_contains "$line" "ballooning context" "skill rule"
  assert_contains "$line" 'checking `ctx`, `elapsed`' "skill rule"
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
  assert_eq 0 "$(find "$(dirname "$(run_file w1.out)")" -maxdepth 1 -name 'w1.zcode-log-*' | wc -l | tr -d ' ')" "zcode logs after a pi fallback"
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
  assert_jq '.fallback_errors == ["overloaded"]' "$entry" "journal fallback_errors"
}

case_fallback_dispatch_error() {
  fallback_spawn
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if (( $3 < 3 )); then
  turn "$2" "partial" error overloaded
else
  printf 'provider refused the request\n' >&2
  exit 2
fi
EOF
  hd_run ask w1 'Do the work.'
  [[ "$HD_RC" != 0 ]] || t_fail "hd ask exit: expected non-zero, got 0"
  assert_not_contains "$HD_OUT" "STATUS: still_working"
  assert_contains "$HD_OUT" "provider refused the request" "dispatch output"
  assert_eq 3 "$(prompt_calls)" "prompt count"
}

case_journal_without_fallback_errors() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "did it
STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_exists "$journal" "journal"
  assert_jq '.fallback_errors == []' "$(tail -n 1 "$journal")" "journal fallback_errors without a fallback"
}

case_fallback_errors_per_switch() {
  printf 'prov m1\nprov m2\nprov m3\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"fallback":[{"model":"prov/m2"},{"model":"prov/m3"}]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if (( $3 < 5 )); then
  turn "$2" "partial" error overloaded
else
  turn "$2" "fixed
STATUS: done"
fi
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_jq '.fallback_errors == ["overloaded","overloaded"]' "$(tail -n 1 "$journal")" "journal fallback_errors per switch"
}

case_fallback_slot_role_changed() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"custom":{"role":"worker","model":"prov/m1","fallback":[{"model":"prov/m2"}]}}}'
  hd_run spawn w1 custom
  assert_eq 0 "$HD_RC" "hd spawn w1 custom"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if (( $3 == 2 )); then
  printf '%s\n' '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"custom":{"role":"reviewer","model":"prov/m1","fallback":[{"model":"prov/m2"}]}}}' > "$HD_CONFIG"
fi
turn "$2" "partial" error overloaded
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask exit"
  assert_contains "$HD_OUT" "STATUS: provider_error"
  assert_contains "$HD_OUT" "fallback skipped: slot custom"
  assert_eq 0 "$(grep -c $'^pane\tclose' "$FAKE_DIR/calls.log" || true)" "pane close calls"
  assert_eq worker "$(cat "$(run_file w1.role)")" ".role"
  assert_file_contains "$(run_file w1.fallback)" "prov/m2" ".fallback"
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
run_case errors_still_working_ask_diagnostics case_still_working_ask_diagnostics
run_case errors_still_working_wait_diagnostics case_still_working_wait_diagnostics
run_case errors_still_working_empty_diagnostics case_still_working_empty_diagnostics
run_case errors_still_working_skill_rule case_still_working_skill_rule
run_case errors_blocked_status case_blocked_status
run_case errors_provider_error_retry case_provider_error_retry
run_case errors_provider_error_twice case_provider_error_twice
run_case errors_fallback_switch case_fallback_switch
run_case errors_fallback_ls_and_journal case_fallback_ls_and_journal
run_case errors_fallback_dispatch_error case_fallback_dispatch_error
run_case errors_journal_without_fallback_errors case_journal_without_fallback_errors
run_case errors_fallback_errors_per_switch case_fallback_errors_per_switch
run_case errors_fallback_slot_role_changed case_fallback_slot_role_changed
run_case errors_fallback_chain_exhausted case_fallback_chain_exhausted
run_case errors_fallback_absent_exhausted case_fallback_absent_exhausted
run_case errors_fallback_resume case_fallback_resume
run_case errors_fallback_used_up case_fallback_used_up
run_case errors_fallback_keeps_out case_fallback_keeps_out
