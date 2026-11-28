#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

spawn_two_scouts() {
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "hd spawn s1"
  hd_run spawn s2 scout
  assert_eq 0 "$HD_RC" "hd spawn s2"
}

write_wait_hook() {
  cat > "$FAKE_DIR/on-wait"
  chmod +x "$FAKE_DIR/on-wait"
}

case_wait_batch_two_agents_parallel_and_delimited() {
  spawn_two_scouts
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "from $1
STATUS: done"
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask s1 'Check file 1.'
  assert_eq 0 "$HD_RC" "ask s1"
  assert_contains "$HD_OUT" "STATUS: still_working" "s1 still working"
  hd_run ask s2 'Check file 2.'
  assert_eq 0 "$HD_RC" "ask s2"
  assert_contains "$HD_OUT" "STATUS: still_working" "s2 still working"

  write_wait_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Both agents must enter wait concurrently; sleep briefly and record overlap.
printf 'start %s\n' "$1" >> "$FAKE_DIR/wait.trace"
sleep 0.2
printf 'end %s\n' "$1" >> "$FAKE_DIR/wait.trace"
exit 0
EOF

  hd_run wait s1 s2 --timeout 30000
  assert_eq 0 "$HD_RC" "hd wait s1 s2"
  assert_contains "$HD_OUT" "=== s1 ===" "s1 header"
  assert_contains "$HD_OUT" "=== s2 ===" "s2 header"
  assert_contains "$HD_OUT" "from s1-" "s1 reply"
  assert_contains "$HD_OUT" "from s2-" "s2 reply"
  # Both must start before either ends (parallel wait).
  local first_two
  first_two="$(head -n 2 "$FAKE_DIR/wait.trace")"
  assert_contains "$first_two" "start s1-" "s1 started in parallel"
  assert_contains "$first_two" "start s2-" "s2 started in parallel"
  # Both settled into journal.
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_eq 2 "$(wc -l < "$journal" | tr -d ' ')" "two journal lines"
}

case_wait_batch_mixed_done_and_still_working() {
  spawn_two_scouts
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "reply $1
STATUS: done"
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask s1 'Check 1.'
  hd_run ask s2 'Check 2.'

  write_wait_hook <<'EOF'
#!/usr/bin/env bash
case "$1" in
  s1-*) exit 0 ;;
  s2-*) exit 1 ;;
esac
EOF

  hd_run wait --timeout 30000 s1 s2
  assert_eq 0 "$HD_RC" "mixed batch wait exit 0"
  assert_contains "$HD_OUT" "=== s1 ===" "s1 header"
  assert_contains "$HD_OUT" "STATUS: done" "s1 done"
  assert_contains "$HD_OUT" "=== s2 ===" "s2 header"
  assert_contains "$HD_OUT" "STATUS: still_working" "s2 still_working"
}

case_wait_single_unchanged_no_header() {
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "spawn s1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "single reply
STATUS: done"
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask s1 'Check 1.'
  hd_run wait s1
  assert_eq 0 "$HD_RC" "single wait"
  assert_contains "$HD_OUT" "single reply" "single reply"
  assert_not_contains "$HD_OUT" "=== s1 ===" "single wait has no batch header"
}

case_wait_batch_rejects_duplicate_name() {
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "spawn s1"
  hd_run wait s1 s1
  assert_eq 1 "$HD_RC" "duplicate wait rejected"
  assert_contains "$HD_OUT" "duplicate agent name in wait: s1" "duplicate error"
}

case_wait_batch_sequential_finish() {
  spawn_two_scouts
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "from $1
STATUS: done"
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask s1 $'Check 1.\nCheck: `printf "start s1\\n" >> "'"$FAKE_DIR"$'/finish.trace"; sleep 0.2; printf "end s1\\n" >> "'"$FAKE_DIR"$'/finish.trace"`'
  assert_eq 0 "$HD_RC" "ask s1"
  hd_run ask s2 $'Check 2.\nCheck: `printf "start s2\\n" >> "'"$FAKE_DIR"$'/finish.trace"; sleep 0.2; printf "end s2\\n" >> "'"$FAKE_DIR"$'/finish.trace"`'
  assert_eq 0 "$HD_RC" "ask s2"

  hd_run wait s1 s2 --timeout 30000
  assert_eq 0 "$HD_RC" "sequential finish wait"
  local expected
  expected=$'start s1\nend s1\nstart s2\nend s2'
  assert_eq "$expected" "$(cat "$FAKE_DIR/finish.trace")" "finish runs sequentially per agent"
}

case_wait_no_double_settle_after_ask_end() {
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "spawn s1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "done once
STATUS: done"
EOF
  hd_run ask s1 $'Check once.\nCheck: `printf "ran\\n" >> "'"$FAKE_DIR"$'/check.count"`'
  assert_eq 0 "$HD_RC" "ask s1"
  assert_eq 1 "$(wc -l < "$FAKE_DIR/check.count" | tr -d ' ')" "check ran once"

  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_eq 1 "$(wc -l < "$journal" | tr -d ' ')" "one journal line after ask"

  hd_run wait s1
  assert_eq 0 "$HD_RC" "repeat wait succeeds"
  assert_contains "$HD_OUT" "done once" "repeat wait prints result"
  assert_eq 1 "$(wc -l < "$FAKE_DIR/check.count" | tr -d ' ')" "check did not re-run"
  assert_eq 1 "$(wc -l < "$journal" | tr -d ' ')" "journal did not duplicate"
}

case_wait_batch_broken_session_preserves_error() {
  spawn_two_scouts
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
case "$1" in
  s1-*) printf '{broken json\n' >> "$2" ;;
  s2-*) turn "$2" "healthy s2
STATUS: done" ;;
esac
printf 'timeout waiting\n'
exit 1
EOF
  hd_run ask s1 'Broken session.'
  assert_eq 0 "$HD_RC" "ask s1"
  hd_run ask s2 'Healthy session.'
  assert_eq 0 "$HD_RC" "ask s2"

  hd_run wait s1 s2 --timeout 30000
  [[ "$HD_RC" -ne 0 ]] || t_fail "expected nonzero exit on broken session, got 0"
  assert_contains "$HD_OUT" "=== s1 ===" "s1 header present"
  assert_contains "$HD_OUT" "=== s2 ===" "s2 header present"
  assert_contains "$HD_OUT" "healthy s2" "healthy agent still settled"
}

run_case wait_batch_two_agents_parallel_and_delimited case_wait_batch_two_agents_parallel_and_delimited
run_case wait_batch_mixed_done_and_still_working case_wait_batch_mixed_done_and_still_working
run_case wait_single_unchanged_no_header case_wait_single_unchanged_no_header
run_case wait_batch_rejects_duplicate_name case_wait_batch_rejects_duplicate_name
run_case wait_batch_sequential_finish case_wait_batch_sequential_finish
run_case wait_no_double_settle_after_ask_end case_wait_no_double_settle_after_ask_end
run_case wait_batch_broken_session_preserves_error case_wait_batch_broken_session_preserves_error
