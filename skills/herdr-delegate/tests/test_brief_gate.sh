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
Removes: nothing
Traps:
- none — fixture
Acceptance:
- Seam: the command under test.
- R1: input-a → expected-a
- R2: input-b → expected-b
Scope: `src/a.txt` `src/b.txt`
Check: `test -f src/a.txt`
EOF
}

emit_brief() {
  local file="$1"
  local requirements="${REQUIREMENTS_SECTION-$'Requirements:\n- R1: the first behavior is observable.\n- R2: the second behavior is observable.'}"
  local removes="${REMOVES_SECTION-Removes: nothing}"
  local traps="${TRAPS_SECTION-$'Traps:\n- none — fixture'}"
  local acceptance="${ACCEPTANCE_SECTION-$'Acceptance:\n- Seam: cli\n- R1: input-a → expected-a\n- R2: input-b → expected-b'}"
  local check='Check: `test -f src/a.txt`'
  [[ -z "${CHECK_SECTION+x}" ]] || check="$CHECK_SECTION"
  cat > "$file" <<EOF
Goal: add two observable behaviors.
Context:
- \`src/a.txt\` holds the input.
Decisions:
- D1: keep the change small.
$requirements
$removes
$traps
$acceptance
Scope: \`src/a.txt\`
$check
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

case_brief_gate_r1_raw() {
  spawn_w1
  done_hook
  cat > raw-brief.md <<'EOF'
Brief: raw
Rename the field in src/a.txt and report.
EOF
  hd_run ask w1 @raw-brief.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a raw brief"
  assert_contains "$HD_OUT" "missing section(s) on their own line:"
  assert_not_contains "$HD_OUT" "Brief: raw"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
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

case_brief_gate_r2_sections() {
  spawn_w1
  done_hook
  REMOVES_SECTION='' TRAPS_SECTION='' \
    ACCEPTANCE_SECTION=$'Acceptance:\n- R1: input-a → expected-a\n- R2: input-b → expected-b' \
    CHECK_SECTION='Check: `true`' emit_brief missing-sections.md
  hd_run ask w1 @missing-sections.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a brief without Removes: or Traps:"
  assert_contains "$HD_OUT" "missing section(s) on their own line: Removes, Traps"
  assert_contains "$HD_OUT" 'Acceptance needs a non-empty "Seam:" line'
  assert_contains "$HD_OUT" "Check must run a real verification command (rejected stub: true)"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  REMOVES_SECTION='Removes:' TRAPS_SECTION='Traps:' emit_brief empty-sections.md
  hd_run ask w1 @empty-sections.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted empty Removes: and Traps:"
  assert_contains "$HD_OUT" "empty section(s): Removes, Traps"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  TRAPS_SECTION=$'Traps:\n   ' emit_brief blank-traps.md
  hd_run ask w1 @blank-traps.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted a Traps: section with only whitespace"
  assert_contains "$HD_OUT" "empty section(s): Traps"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  valid_brief valid-brief.md
  hd_run ask w1 @valid-brief.md
  assert_eq 0 "$HD_RC" "hd ask with explicit empty values"
  assert_contains "$HD_OUT" "STATUS: done"
}

case_brief_gate_r3_seam_missing() {
  spawn_w1
  done_hook
  ACCEPTANCE_SECTION=$'Acceptance:\n- R1: input-a → expected-a\n- R2: input-b → expected-b' emit_brief no-seam.md
  hd_run ask w1 @no-seam.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted Acceptance: without Seam:"
  assert_contains "$HD_OUT" 'Acceptance needs a non-empty "Seam:" line'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  ACCEPTANCE_SECTION=$'Acceptance:\n- Seam:   \n- R1: input-a → expected-a\n- R2: input-b → expected-b' emit_brief empty-seam.md
  hd_run ask w1 @empty-seam.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted an empty Seam: line"
  assert_contains "$HD_OUT" 'Acceptance needs a non-empty "Seam:" line'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r3_seam_dash() {
  spawn_w1
  done_hook
  ACCEPTANCE_SECTION=$'Acceptance:\n- Seam: the command under test.\n- R1: input-a → expected-a\n- R2: input-b → expected-b' emit_brief dash-seam.md
  hd_run ask w1 @dash-seam.md
  assert_eq 0 "$HD_RC" "hd ask with - Seam:"
  assert_contains "$HD_OUT" "STATUS: done"
}

case_brief_gate_r3_seam_plain() {
  spawn_w1
  done_hook
  ACCEPTANCE_SECTION=$'Acceptance:\nSeam: the command under test.\n- R1: input-a → expected-a\n- R2: input-b → expected-b' emit_brief plain-seam.md
  hd_run ask w1 @plain-seam.md
  assert_eq 0 "$HD_RC" "hd ask with plain Seam:"
  assert_contains "$HD_OUT" "STATUS: done"
}

case_brief_gate_r4_coverage() {
  spawn_w1
  done_hook
  ACCEPTANCE_SECTION=$'Acceptance:\n- Seam: cli\n- R1: a → b\n- R1: c → d\n- R2: run red → green' emit_brief red-green-missing.md
  hd_run ask w1 @red-green-missing.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask counted two R1 cases as covering R2"
  assert_contains "$HD_OUT" 'Acceptance missing "input → expected" case line(s) for: R2'
  assert_not_contains "$HD_OUT" 'Acceptance needs at least 2'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  ACCEPTANCE_SECTION=$'Acceptance:\n- Seam: cli\n- R1: a → b\n- R1: c → d\n- R2: check it' emit_brief prose-missing.md
  hd_run ask w1 @prose-missing.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask counted R2 prose as a case"
  assert_contains "$HD_OUT" 'Acceptance missing "input → expected" case line(s) for: R2'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"

  REQUIREMENTS_SECTION=$'Requirements:\n- R1: the first behavior is observable.\n- R10: the tenth behavior is observable.' \
    ACCEPTANCE_SECTION=$'Acceptance:\n- Seam: cli\n- R10: x → y' emit_brief token-collision.md
  hd_run ask w1 @token-collision.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask let R10 cover R1"
  assert_contains "$HD_OUT" 'Acceptance missing "input → expected" case line(s) for: R1'
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r5_stubs() {
  spawn_w1
  done_hook
  local stub
  for stub in true : 'git diff --check' 'npx jest --listTests'; do
    CHECK_SECTION="Check: \`$stub\`" emit_brief check-stub.md
    hd_run ask w1 @check-stub.md
    [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted stub Check: $stub"
    assert_contains "$HD_OUT" "Check must run a real verification command (rejected stub: $stub)"
    assert_eq 0 "$(prompt_calls)" "agent prompt calls"
  done
  CHECK_SECTION='Check: ' emit_brief check-empty.md
  hd_run ask w1 @check-empty.md
  [[ "$HD_RC" -ne 0 ]] || t_fail "hd ask accepted an empty Check:"
  assert_contains "$HD_OUT" "Check command cannot be empty"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_brief_gate_r5_real_check() {
  spawn_w1
  done_hook
  CHECK_SECTION='Check: `test -f src/a.txt`' emit_brief real-check.md
  hd_run ask w1 @real-check.md
  assert_eq 0 "$HD_RC" "hd ask with a real Check:"
  assert_contains "$HD_OUT" "STATUS: done"
}

case_brief_gate_r5_chained_check() {
  spawn_w1
  done_hook
  CHECK_SECTION='Check: `git diff --check && test -f src/a.txt`' emit_brief chained-check.md
  hd_run ask w1 @chained-check.md
  assert_eq 0 "$HD_RC" "hd ask with a chained Check:"
  assert_contains "$HD_OUT" "STATUS: done"
}

case_brief_gate_r6_docs() {
  local brief_doc="$(dirname "$ROOT")/brief/SKILL.md"
  assert_file_not_contains "$ROOT/SKILL.md" 'Brief: raw'
  assert_file_contains "$ROOT/SKILL.md" 'Removes:'
  assert_file_contains "$ROOT/SKILL.md" 'Traps:'
  assert_file_contains "$ROOT/SKILL.md" 'Seam:'
  assert_file_contains "$brief_doc" 'none — <reason>'
}

run_case brief_gate_r1_missing case_brief_gate_r1_missing
run_case brief_gate_r1_shorthand case_brief_gate_r1_shorthand
run_case brief_gate_r1_scope case_brief_gate_r1_scope
run_case brief_gate_r2_valid case_brief_gate_r2_valid
run_case brief_gate_r1_raw case_brief_gate_r1_raw
run_case brief_gate_r3_followup case_brief_gate_r3_followup
run_case brief_gate_r2_sections case_brief_gate_r2_sections
run_case brief_gate_r3_seam_missing case_brief_gate_r3_seam_missing
run_case brief_gate_r3_seam_dash case_brief_gate_r3_seam_dash
run_case brief_gate_r3_seam_plain case_brief_gate_r3_seam_plain
run_case brief_gate_r4_coverage case_brief_gate_r4_coverage
run_case brief_gate_r5_stubs case_brief_gate_r5_stubs
run_case brief_gate_r5_real_check case_brief_gate_r5_real_check
run_case brief_gate_r5_chained_check case_brief_gate_r5_chained_check
run_case brief_gate_r6_docs case_brief_gate_r6_docs
run_case brief_gate_r3_scout case_brief_gate_r3_scout
run_case brief_gate_r4_one_line_arrows case_brief_gate_r4_one_line_arrows
run_case brief_gate_r4_red_green case_brief_gate_r4_red_green
run_case brief_gate_r1_retry_still_seq1 case_brief_gate_r1_retry_still_seq1
