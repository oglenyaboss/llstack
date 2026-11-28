#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_review_models() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"review-a":{"role":"reviewer","model":"prov/m1"},"review-b":{"role":"reviewer","model":"prov/m2"}}}'
}

done_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
turn "$2" "No findings.
STATUS: done"
EOF
}

case_review_allows_different_models_same_head() {
  setup_review_models
  done_hook
  hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva"
  hd_run spawn rvb review-b
  assert_eq 0 "$HD_RC" "spawn rvb"

  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "ask rva"
  assert_contains "$HD_OUT" "STATUS: done" "rva done"

  hd_run ask rvb 'Review HEAD.'
  assert_eq 0 "$HD_RC" "ask rvb"
  assert_contains "$HD_OUT" "STATUS: done" "rvb done"
}

case_review_blocks_duplicate_model_same_head_until_force() {
  setup_review_models
  done_hook
  hd_run spawn rva review-a
  hd_run spawn rvc review-a
  assert_eq 0 "$HD_RC" "spawn rvc"

  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "ask rva"

  hd_run ask rvc 'Duplicate review of HEAD.'
  assert_eq 1 "$HD_RC" "duplicate model refused"
  assert_contains "$HD_OUT" "model prov/m1 already reviewed" "duplicate model reason"
  assert_contains "$HD_OUT" "--force" "force hint"

  hd_run ask rvc 'Forced duplicate review.' --force
  assert_eq 0 "$HD_RC" "forced duplicate allowed"
  assert_contains "$HD_OUT" "STATUS: done" "rvc done"
}

case_review_blocks_third_round_on_same_branch_until_force() {
  setup_review_models
  done_hook
  hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva"

  # Round 1 on commit 1
  hd_run ask rva 'Round 1 review.'
  assert_eq 0 "$HD_RC" "round 1"

  # Commit fix -> Round 2 on commit 2 (allowed)
  printf 'fix1\n' >> src/a.txt
  git add src/a.txt
  git -c user.name=test -c user.email=test@example.com commit -qm fix1
  hd_run ask rva 'Round 2 re-review.'
  assert_eq 0 "$HD_RC" "round 2 allowed"

  # Commit fix2 -> Round 3 on commit 3 (blocked)
  printf 'fix2\n' >> src/a.txt
  git add src/a.txt
  git -c user.name=test -c user.email=test@example.com commit -qm fix2
  hd_run ask rva 'Round 3 review.'
  assert_eq 1 "$HD_RC" "round 3 refused"
  assert_contains "$HD_OUT" "already has 2 review rounds" "round cap reason"
  assert_contains "$HD_OUT" "--force" "force hint"

  # Override with --force
  hd_run ask rva 'Forced round 3 review.' --force
  assert_eq 0 "$HD_RC" "forced round 3 allowed"
  assert_contains "$HD_OUT" "STATUS: done" "round 3 forced done"
}

case_review_retry_after_needs_decision_not_blocked() {
  setup_review_models
  hd_run spawn rva review-a
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
if [[ "$3" == 1 ]]; then
  turn "$2" "Need spec clarification.
STATUS: needs_decision"
else
  turn "$2" "No findings.
STATUS: done"
fi
EOF
  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "first ask needs_decision"
  assert_contains "$HD_OUT" "STATUS: needs_decision" "needs_decision"

  hd_run ask rva 'Clarification: option A.'
  assert_eq 0 "$HD_RC" "follow-up after needs_decision allowed"
  assert_contains "$HD_OUT" "STATUS: done" "follow-up done"
}

case_review_fallback_credits_replacement_model() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"review-a":{"role":"reviewer","model":"prov/m1","fallback":[{"model":"prov/m2"}]},"review-a-plain":{"role":"reviewer","model":"prov/m1"},"review-b":{"role":"reviewer","model":"prov/m2"}}}'
  hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
count_file="$FAKE_DIR/attempt.count"
n=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" > "$count_file"
if (( n <= 2 )); then
  turn "$2" "" error "HTTP 429 rate limit"
else
  write_payload "$1"
  turn "$2" "No findings.
STATUS: done"
fi
EOF
  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "fallback review succeeds"
  assert_contains "$HD_OUT" "fallback: prov/m1 → prov/m2" "fell back to m2"
  assert_contains "$HD_OUT" "STATUS: done" "fallback done"

  hd_run spawn rvb review-b
  assert_eq 0 "$HD_RC" "spawn rvb"
  hd_run ask rvb 'Duplicate replacement model.'
  assert_eq 1 "$HD_RC" "replacement model m2 blocked as duplicate"
  assert_contains "$HD_OUT" "model prov/m2 already reviewed" "credits m2"

  hd_run spawn rva2 review-a-plain
  assert_eq 0 "$HD_RC" "spawn rva2"
  hd_run ask rva2 'Retry original failed model.'
  assert_eq 0 "$HD_RC" "failed initial model m1 still allowed"
  assert_contains "$HD_OUT" "STATUS: done" "m1 retry done"
}

case_review_persists_across_lead_panes() {
  setup_review_models
  done_hook
  hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva in p0"
  hd_run ask rva 'Review HEAD in pane 0.'
  assert_eq 0 "$HD_RC" "ask rva in p0"

  HERDR_PANE_ID=test:p1 hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva in p1"
  HERDR_PANE_ID=test:p1 hd_run ask rva 'Duplicate review from pane 1.'
  assert_eq 1 "$HD_RC" "duplicate across panes refused"
  assert_contains "$HD_OUT" "model prov/m1 already reviewed" "cross-pane duplicate reason"
}

case_review_prose_status_done_with_needs_decision() {
  setup_review_models
  hd_run spawn rva review-a
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
if [[ "$3" == 1 ]]; then
  turn "$2" "I cannot emit STATUS: done until you answer.
STATUS: needs_decision"
else
  turn "$2" "No findings.
STATUS: done"
fi
EOF
  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "needs_decision ask"
  assert_contains "$HD_OUT" "STATUS: needs_decision" "needs_decision returned"

  hd_run ask rva 'Answer.'
  assert_eq 0 "$HD_RC" "follow-up allowed despite prose STATUS: done"
  assert_contains "$HD_OUT" "STATUS: done" "follow-up done"
}

case_review_missing_output_file_not_counted() {
  setup_review_models
  hd_run spawn rva review-a
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  turn "$2" "No findings.
STATUS: done"
else
  write_payload "$1"
  turn "$2" "No findings.
STATUS: done"
fi
EOF
  hd_run ask rva 'Review HEAD without writing output.'
  assert_eq 0 "$HD_RC" "first ask without payload"

  hd_run ask rva 'Retry and write OUTPUT_FILE.'
  assert_eq 0 "$HD_RC" "retry allowed when first had no output file"
  assert_contains "$HD_OUT" "STATUS: done" "second ask done"

  hd_run ask rva 'Third ask should now be blocked.'
  assert_eq 1 "$HD_RC" "third ask blocked after valid payload"
  assert_contains "$HD_OUT" "model prov/m1 already reviewed" "duplicate blocked"
}

case_review_thinking_suffix_same_model() {
  printf 'prov m1\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"review-a":{"role":"reviewer","model":"prov/m1"},"review-a-high":{"role":"reviewer","model":"prov/m1:high"}}}'
  done_hook
  hd_run spawn rva review-a
  assert_eq 0 "$HD_RC" "spawn rva"
  hd_run ask rva 'Review HEAD.'
  assert_eq 0 "$HD_RC" "ask rva"

  hd_run spawn rvah review-a-high
  assert_eq 0 "$HD_RC" "spawn rvah"
  hd_run ask rvah 'Review HEAD with thinking suffix.'
  assert_eq 1 "$HD_RC" "thinking suffix normalized as duplicate"
  assert_contains "$HD_OUT" "model prov/m1 already reviewed" "normalized model in error"
}

case_issue_ready_template_passes_worker_brief_gate() {
  done_hook
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "spawn w1"
  local tpl="$ROOT/../issue-workflow/templates/issue-ready.md"
  assert_exists "$tpl" "issue-ready template"
  # Fill placeholders while preserving every section header and structure from the template.
  sed \
    -e 's/<one sentence, the observable result>/Return normalized slug for input./' \
    -e 's/`<sha>`/`deadbeef`/' \
    -e 's/<fact> → `path\/to\/file:line`/Helper lives at `src\/a.txt:1`/' \
    -e 's/`path\/to\/file:start-end` (or `none`)/none/' \
    -e 's/`path\/to\/test` (or `none`)/none/' \
    -e 's/<verbatim answer from the decision owner, or "Not required: <one line why>". ADR link when the decision constrains future behavior.>/Not required: internal helper./' \
    -e 's/<technical choice where the code leaves a choice open, or omit if none>/Lowercase ASCII only./' \
    -e 's/<one observable behavior>/Lowercases ASCII input./' \
    -e 's/<what is removed or replaced, or "nothing">/nothing/' \
    -e 's/<where a plausible implementation goes wrong, with the correct shape> (or `none — <reason>`)/none — pure string helper/' \
    -e 's/<public function, endpoint, component, or CLI command>/slugify(input)/' \
    -e 's/<concrete input> → <exact expected literal>/"Hello" → "hello"/' \
    -e 's/<edge input> → <exact expected result>/R2: "" → ""/' \
    -e 's|`path/to/file` `tests/file.test.ts`|`src/a.txt`|' \
    -e 's|<one shell command proving Done when>|test -f src/a.txt|' \
    "$tpl" > "$CASE_TMP/issue-brief.md"
  hd_run ask w1 "@$CASE_TMP/issue-brief.md"
  assert_eq 0 "$HD_RC" "issue-ready template passes validate_worker_brief"
  assert_contains "$HD_OUT" "STATUS: done" "worker completed"
}

run_case review_allows_different_models_same_head case_review_allows_different_models_same_head
run_case review_blocks_duplicate_model_same_head_until_force case_review_blocks_duplicate_model_same_head_until_force
run_case review_blocks_third_round_on_same_branch_until_force case_review_blocks_third_round_on_same_branch_until_force
run_case review_retry_after_needs_decision_not_blocked case_review_retry_after_needs_decision_not_blocked
run_case review_fallback_credits_replacement_model case_review_fallback_credits_replacement_model
run_case review_persists_across_lead_panes case_review_persists_across_lead_panes
run_case review_prose_status_done_with_needs_decision case_review_prose_status_done_with_needs_decision
run_case review_missing_output_file_not_counted case_review_missing_output_file_not_counted
run_case review_thinking_suffix_same_model case_review_thinking_suffix_same_model
run_case issue_ready_template_passes_worker_brief_gate case_issue_ready_template_passes_worker_brief_gate
