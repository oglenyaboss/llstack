#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

spawn_w1() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_calls_nonempty
}

done_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "did it
STATUS: done"
EOF
}

valid_brief() {
  local file="$1"
  cat > "$file" <<'EOF'
Goal: add two observable behaviors.
Context:
- `src/a.txt` holds the input the executor reads first.
Decisions:
- D1: keep the change inside the two source files.
Requirements:
- R1: the first behavior is observable.
- R2: the second behavior is observable.
Acceptance:
- Seam: the command under test.
- R1: input-a → expected-a
- R2: input-b → expected-b
Scope: `src/a.txt` `src/b.txt`
Check: `true`
EOF
}

shorthand_brief() {
  local file="$1"
  cat > "$file" <<'EOF'
Goal: add three observable behaviors.
Context:
- `src/a.txt` holds the input.
Decisions:
- D1: keep the change small.
Requirements:
- R1: the first behavior is observable.
- R2: the second behavior is observable.
- R3: the third behavior is observable.
Acceptance: tests for R1-R3
Scope: `src/a.txt`
Check: `true`
EOF
}

case_brief_gate_r1_missing() {
  spawn_w1
  done_hook
  printf 'Goal: add a widget. Context: none. Decisions: none. Requirements: R1. Acceptance: a -> b. Scope: `src/`. Check: `true`\n' > one-line-brief.md
  hd_run ask w1 @one-line-brief.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a one-line brief"
  assert_contains "$HD_OUT" "missing section(s) on their own line:"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
  assert_eq "" "$(find "$XDG_CACHE_HOME/herdr-delegate" -name 'w1-01.brief' -print 2>/dev/null || true)" "state written by the rejected ask"
}

case_brief_gate_r1_shorthand() {
  spawn_w1
  done_hook
  shorthand_brief shorthand-brief.md
  hd_run ask w1 @shorthand-brief.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a shorthand brief"
  assert_contains "$HD_OUT" 'Acceptance needs at least 3 "input → expected" case line(s)'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r1_scope() {
  spawn_w1
  done_hook
  cat > no-backtick-scope.md <<'EOF'
Goal: move the stage.
Context:
- `src/a.txt` holds the input.
Decisions:
- D1: keep the change inside the task.
Requirements:
- R1: moving it works.
Acceptance:
- R1: running x → prints y
Scope: internal/stage/
Check: `true`
EOF
  hd_run ask w1 @no-backtick-scope.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a Scope without a backticked path"
  assert_contains "$HD_OUT" "Scope needs at least one backticked path"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r2_valid() {
  spawn_w1
  done_hook
  valid_brief valid-brief.md
  hd_run ask w1 @valid-brief.md
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "STATUS: done"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r3_raw() {
  spawn_w1
  done_hook
  cat > raw-brief.md <<'EOF'
Brief: raw
Rename the field in src/a.txt and report.
EOF
  hd_run ask w1 @raw-brief.md
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "STATUS: done"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r3_followup() {
  spawn_w1
  done_hook
  valid_brief valid-brief.md
  hd_run ask w1 @valid-brief.md
  assert_eq 0 "$HD_RC" "first ask"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls after the first ask"
  printf 'Decision: (a).\n' > followup.md
  hd_run ask w1 @followup.md
  assert_eq 0 "$HD_RC" "follow-up ask"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls after the follow-up"
}

case_brief_gate_r3_scout() {
  hd_run spawn sc scout
  assert_eq 0 "$HD_RC" "hd spawn sc"
  done_hook
  printf 'Goal: map the auth flow.\n' > scout-brief.md
  hd_run ask sc @scout-brief.md
  assert_eq 0 "$HD_RC" "scout ask"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r4_one_line_arrows() {
  spawn_w1
  done_hook
  cat > crammed-arrows.md <<'EOF'
Goal: add two observable behaviors.
Context:
- `src/a.txt` holds the input.
Decisions:
- D1: keep the change small.
Requirements:
- R1: the first behavior is observable.
- R2: the second behavior is observable.
Acceptance: a -> b; c -> d
Scope: `src/a.txt`
Check: `true`
EOF
  hd_run ask w1 @crammed-arrows.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask counted two arrows on one line as two cases"
  assert_contains "$HD_OUT" 'Acceptance needs at least 2 "input → expected" case line(s) (one per line), found 1'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r4_red_green() {
  spawn_w1
  done_hook
  cat > red-green-only.md <<'EOF'
Goal: add one observable behavior.
Context:
- `src/a.txt` holds the input.
Decisions:
- D1: keep the change small.
Requirements:
- R1: the behavior is observable.
Acceptance:
- Run TDD red → green
Scope: `src/a.txt`
Check: `true`
EOF
  hd_run ask w1 @red-green-only.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask counted red → green as an Acceptance case"
  assert_contains "$HD_OUT" 'Acceptance needs at least 1 "input → expected" case line(s) (one per line), found 0'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
  cat > red-green-dash.md <<'EOF'
Goal: add one observable behavior.
Context:
- `src/a.txt` holds the input.
Decisions:
- D1: keep the change small.
Requirements:
- R1: the behavior is observable.
Acceptance:
- Run TDD red -> green
Scope: `src/a.txt`
Check: `true`
EOF
  hd_run ask w1 @red-green-dash.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask counted red -> green as an Acceptance case"
  assert_contains "$HD_OUT" 'Acceptance needs at least 1 "input → expected" case line(s) (one per line), found 0'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r1_retry_still_seq1() {
  spawn_w1
  done_hook
  shorthand_brief shorthand-brief.md
  hd_run ask w1 @shorthand-brief.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a shorthand brief"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls after the first rejection"
  hd_run ask w1 @shorthand-brief.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "the second ask skipped the gate: seq moved past 1"
  assert_contains "$HD_OUT" 'Acceptance needs at least 3 "input → expected" case line(s)'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls after the second rejection"
  valid_brief valid-brief.md
  hd_run ask w1 @valid-brief.md
  assert_eq 0 "$HD_RC" "corrected ask"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls after the corrected ask"
  local brief_path
  brief_path="$(find "$XDG_CACHE_HOME/herdr-delegate" -name 'w1-01.brief' -print -quit 2>/dev/null || true)"
  [[ -n "$brief_path" ]] || t_fail "the corrected ask was not written as w1-01.brief"
}

run_case brief_gate_r1_missing case_brief_gate_r1_missing
run_case brief_gate_r1_shorthand case_brief_gate_r1_shorthand
run_case brief_gate_r1_scope case_brief_gate_r1_scope
run_case brief_gate_r2_valid case_brief_gate_r2_valid
run_case brief_gate_r3_raw case_brief_gate_r3_raw
run_case brief_gate_r3_followup case_brief_gate_r3_followup
run_case brief_gate_r3_scout case_brief_gate_r3_scout
run_case brief_gate_r4_one_line_arrows case_brief_gate_r4_one_line_arrows
run_case brief_gate_r4_red_green case_brief_gate_r4_red_green
run_case brief_gate_r1_retry_still_seq1 case_brief_gate_r1_retry_still_seq1
