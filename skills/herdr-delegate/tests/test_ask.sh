#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

spawn_w1() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_calls_nonempty
}

state_file() {
  local path
  path="$(find "$XDG_CACHE_HOME/herdr-delegate" -name "$1" -print -quit)"
  [[ -n "$path" ]] || t_fail "no state file $1"
  printf '%s\n' "$path"
}

agent_prompt_calls() {
  grep -c $'^agent\tprompt\t'"$1-" "$FAKE_DIR/calls.log" 2>/dev/null || true
}

no_state_file() {
  [[ -z "$(find "$XDG_CACHE_HOME/herdr-delegate" -name "$1" -print -quit)" ]]
}

journal_entry() {
  jq -c --arg name "$1" 'select(.name == $name)' "$XDG_CACHE_HOME/herdr-delegate/journal.jsonl" | tail -n 1
}

case_reply_check_scope() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src
printf 'b\n' > src/b.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`
Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "did it"
  assert_contains "$HD_OUT" "ctx=3k"
  assert_contains "$HD_OUT" "--- check: test -f src/b.txt"
  assert_contains "$HD_OUT" "exit=0"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 0 outside Scope"
  assert_calls_nonempty
}

case_claims_reviewer() {
  setup_claims reviewer
  CLAIMS_FIRST=$'### F1 [high] wrong value\n`src/a.txt:2` — `l9`' CLAIMS_NEXT='`src/a.txt:9` — `l9`' hd_run ask w1 'Review src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 1 not found"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

case_claims_reviewer_no_findings() {
  setup_claims reviewer
  CLAIMS_FIRST=$'## Findings\nNo findings.\n## Checked\n- src/a.txt' hd_run ask w1 'Review src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_contains "$HD_OUT" "STATUS: done"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_reviewer_absent() {
  setup_claims reviewer
  mkdir -p tests
  printf 'callFoo()\n' > tests/x_test.go
  git add tests/x_test.go
  CLAIMS_FIRST='ABSENT: `callFoo(`' CLAIMS_NEXT='callFoo( occurs in tests/x_test.go:1, a test' hd_run ask w1 'Find callFoo.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 1 absent found"
  assert_contains "$HD_OUT" "--- claims: 0 cited, 0 not found; 0 absent, 0 found in repo"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

case_scope_reviewer_without_scope() {
  hd_run spawn w1 reviewer
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
printf 'changed\n' >> src/a.txt
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Review the change.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 1 outside Scope"
  assert_contains "$HD_OUT" "src/a.txt"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_autofix_scope_reviewer() {
  hd_run spawn w1 reviewer
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
printf 'changed\n' >> src/a.txt
turn "$2" "STATUS: done"
EOF
  local brief='Review the change.

Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: outside Scope: src/a.txt"
}

case_scope_worker_without_scope() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
printf 'changed\n' >> src/a.txt
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_not_contains "$HD_OUT" "--- scope"
}

case_scope_scout_without_scope() {
  hd_run spawn w1 scout
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
printf 'changed\n' >> src/a.txt
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Read the change.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 1 outside Scope"
  assert_contains "$HD_OUT" "src/a.txt"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_scope_outside_file() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src
printf 'b\n' > src/b.txt
printf 'other\n' > other.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 2 changed, 1 outside Scope"
  assert_after "$HD_OUT" "--- scope: 2 changed, 1 outside Scope" "other.txt"
}

case_scope_directory_and_glob() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src/x tests
printf 'x\n' > src/x/y.txt
printf 't\n' > tests/t.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Scope: `src/` `tests/*.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 2 changed, 0 outside Scope"
}

case_journal_ask_line() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
write_payload "$1"
mkdir -p src
printf 'b\n' > src/b.txt
printf 'other\n' > other.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`
Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl" entry brief_path payload_path
  assert_exists "$journal" "journal"
  assert_eq 1 "$(( $(wc -l < "$journal") ))" "journal line count"
  entry="$(jq -c 'select(.event == "ask")' "$journal")"
  assert_jq '.event == "ask"' "$entry" "journal event"
  assert_jq '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$")' "$entry" "journal ts"
  assert_jq '.status == "STATUS: done"' "$entry" "journal status"
  assert_jq '.check_exit == "0"' "$entry" "journal check_exit"
  assert_jq '.outside_scope == ["other.txt"]' "$entry" "journal outside_scope"
  brief_path="$(jq -r '.brief' <<< "$entry")"
  payload_path="$(jq -r '.payload' <<< "$entry")"
  assert_exists "$brief_path" "journal brief"
  assert_exists "$payload_path" "journal payload"
  assert_eq "$brief" "$(cat "$brief_path")" "journal brief content"
}

case_diff_ignores_pre_dirty_file() {
  spawn_w1
  printf 'dirty\n' >> src/a.txt
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src
printf 'b\n' > src/b.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 0 outside Scope"
  assert_not_contains "$HD_OUT" "src/a.txt" "scope"
  hd_run diff w1
  assert_eq 0 "$HD_RC" "hd diff"
  assert_contains "$HD_OUT" "src/b.txt" "hd diff"
  assert_not_contains "$HD_OUT" "src/a.txt" "hd diff"
}

case_prompt_output_file() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Scope: `src/a.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  local dir prompt line path prefix
  dir="$(single_agent_dir)"
  prompt="$dir/last-prompt"
  assert_exists "$prompt" "prompt"
  line="$(grep '^OUTPUT_FILE: ' "$prompt" | tail -n 1)"
  [[ -n "$line" ]] || t_fail "prompt has no OUTPUT_FILE line"
  path="${line#OUTPUT_FILE: }"
  prefix="$XDG_CACHE_HOME/herdr-delegate/"
  [[ "$path" == "$prefix"* ]] || t_fail "OUTPUT_FILE path [$path] is not under [$prefix]"
  local tail_block
  tail_block="$(tail -n 2 "$prompt")"
  assert_contains "$tail_block" "OUTPUT_FILE: $path" "prompt tail"
  assert_contains "$tail_block" "Write the payload" "prompt tail"
}

case_ask_spawns_sidekick() {
  printf 'Do sidekick work.\n\nCheck: `true`\n' > sidekick-brief.md
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "sidekick done
STATUS: done"
EOF
  hd_run ask sk @sidekick-brief.md
  assert_eq 0 "$HD_RC" "hd ask sk"
  local dir
  dir="$(single_agent_dir)"
  assert_file_contains "$dir/start.args" "roles/sidekick.md"
  assert_file_contains "$FAKE_DIR/calls.log" "roles/sidekick.md" "agent start call"
  assert_calls_nonempty
}

case_scope_in_repo_without_index() {
  rm -rf .git src
  git init -q
  spawn_w1
  write_hook <<'EOF2'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
printf 'n\n' > new.txt
turn "$2" "did it
STATUS: done"
EOF2
  local brief='Do the work.

Scope: `new.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 0 outside Scope"
  assert_not_contains "$HD_OUT" "fatal:"
}

case_check_gtimeout_fallback() {
  spawn_w1
  [[ -n "$TIMEOUT" ]] || t_fail "this case needs timeout or gtimeout"
  local fake_gt="$CASE_TMP/fake-gtimeout"
  mkdir -p "$fake_gt"
  cat > "$fake_gt/gtimeout" <<EOF
#!/usr/bin/env bash
printf 'gtimeout\\n' >> "\$FAKE_DIR/gtimeout.log"
exec "$TIMEOUT" "\$@"
EOF
  chmod +x "$fake_gt/gtimeout"
  export PATH="$fake_gt:$(path_without timeout)"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src
printf 'b\n' > src/b.txt
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask through gtimeout"
  assert_contains "$HD_OUT" "--- check: test -f src/b.txt"
  assert_contains "$HD_OUT" "exit=0"
  assert_exists "$FAKE_DIR/gtimeout.log" "gtimeout log"
}

case_check_without_timeout() {
  spawn_w1
  export PATH="$(path_without timeout gtimeout)"
  local brief='Do the work.

Check: `true`'
  hd_run ask w1 "$brief"
  assert_eq 1 "$HD_RC" "hd ask without a timeout binary"
  assert_contains "$HD_OUT" "Check needs timeout or gtimeout"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
  assert_eq "" "$(find "$XDG_CACHE_HOME/herdr-delegate" -name '*.brief' -o -name '*.check')" "state left by the refused ask"
}

case_ask_without_timeout_no_check() {
  spawn_w1
  export PATH="$(path_without timeout gtimeout)"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "did it
STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask without a Check line"
  assert_contains "$HD_OUT" "did it"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}


case_check_without_backticks() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p src
printf 'b\n' > src/b.txt
turn "$2" "did it
STATUS: done"
EOF
  hd_run ask w1 $'Do the work.\n\nCheck: test -f src/b.txt  \nScope: `src/b.txt`'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" $'--- check: test -f src/b.txt\nexit=0'
}

case_concurrent_ask() {
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "hd spawn s1"
  hd_run spawn s2 scout
  assert_eq 0 "$HD_RC" "hd spawn s2"
  mkdir -p "$CASE_TMP/elsewhere"
  hd_run spawn s3 scout --cwd "$CASE_TMP/elsewhere"
  assert_eq 0 "$HD_RC" "hd spawn s3"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  s1-*)
    "$HD" ask s2 'Other work.' > "$FAKE_DIR/s2.out"
    mkdir -p src
    printf 'b\n' > src/b.txt ;;
  s2-*) printf 'other\n' > other.txt ;;
esac
turn "$2" "did it
STATUS: done"
EOF
  hd_run ask s3 'Before.'
  assert_eq 0 "$HD_RC" "hd ask s3"
  sleep 1
  hd_run ask s1 $'Do the work.\n\nScope: `src/b.txt`'
  assert_eq 0 "$HD_RC" "hd ask s1"
  assert_contains "$HD_OUT" '--- concurrent: s2 ' "s1 names s2"
  assert_contains "$(cat "$FAKE_DIR/s2.out")" '--- concurrent: s1 ' "s2 names s1"
  assert_jq '.concurrent == ["s2"]' "$(journal_entry s1)" "s1 journal"
  assert_jq '.concurrent == []' "$(journal_entry s3)" "s3 journal"
  sleep 1
  hd_run ask s2 'After.'
  assert_eq 0 "$HD_RC" "hd ask s2 after"
  assert_not_contains "$HD_OUT" '--- concurrent' "sequential ask"
}

case_worker_exclusivity_same_tree() {
  local root
  root="$(git rev-parse --show-toplevel)"
  mkdir -p "$CASE_TMP/driver"
  hd_run spawn d1 scout --cwd "$CASE_TMP/driver"
  assert_eq 0 "$HD_RC" "hd spawn d1"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  hd_run spawn w2 worker --cwd "$CASE_TMP/work/src"
  assert_eq 0 "$HD_RC" "hd spawn w2 in a subdirectory"
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "hd spawn s1"
  hd_run spawn rv1 reviewer
  assert_eq 0 "$HD_RC" "hd spawn rv1"
  hd_run spawn sk1 sidekick
  assert_eq 0 "$HD_RC" "hd spawn sk1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  d1-*)
    rc=0
    "$HD" ask w1 'Do the work.' > "$FAKE_DIR/w1.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/w1.rc"
    rc=0
    "$HD" ask w2 'Do the work.' > "$FAKE_DIR/w2.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/w2.rc"
    rc=0
    "$HD" ask s1 'Read src/a.txt.' > "$FAKE_DIR/s1.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/s1.rc"
    rc=0
    "$HD" ask rv1 'Review src/a.txt.' > "$FAKE_DIR/rv1.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/rv1.rc"
    rc=0
    "$HD" ask sk1 'Run a check.' > "$FAKE_DIR/sk1.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/sk1.rc"
    printf 'timeout waiting\n'
    exit 1 ;;
  w1-*) printf 'timeout waiting\n'; exit 1 ;;
esac
turn "$2" "STATUS: done"
EOF
  hd_run ask d1 'Drive the checks.'
  assert_eq 0 "$HD_RC" "driver ask"
  assert_contains "$HD_OUT" 'STATUS: still_working' "driver stays active"
  assert_eq 0 "$(cat "$FAKE_DIR/w1.rc")" "active w1 ask"
  assert_exists "$(state_file w1.ask-start)" "w1 is active"
  no_state_file w1.ask-end || t_fail "active w1 has an end marker"

  assert_eq 1 "$(cat "$FAKE_DIR/w2.rc")" "worker blocked in the same tree"
  assert_contains "$(cat "$FAKE_DIR/w2.out")" "hd: cannot ask worker w2: active ask in $root (w1 (worker)); wait for it to finish, or run w2 in its own git worktree (--cwd)" "worker refusal"
  assert_eq 0 "$(agent_prompt_calls w2)" "blocked worker got no prompt"
  no_state_file w2.ask-start || t_fail "blocked worker wrote an ask-start"

  assert_eq 1 "$(cat "$FAKE_DIR/s1.rc")" "scout blocked by a worker"
  assert_contains "$(cat "$FAKE_DIR/s1.out")" "hd: cannot ask scout s1: active worker in $root (w1 (worker)); wait for it to finish, or run the worker in its own git worktree (--cwd)" "scout refusal"
  assert_eq 0 "$(agent_prompt_calls s1)" "blocked scout got no prompt"
  no_state_file s1.ask-start || t_fail "blocked scout wrote an ask-start"

  local pair other role
  for pair in rv1:reviewer sk1:sidekick; do
    other="${pair%%:*}"
    role="${pair#*:}"
    assert_eq 1 "$(cat "$FAKE_DIR/$other.rc")" "$other blocked by a worker"
    assert_contains "$(cat "$FAKE_DIR/$other.out")" "hd: cannot ask $role $other: active worker in $root (w1 (worker)); wait for it to finish, or run the worker in its own git worktree (--cwd)" "$other refusal"
    assert_eq 0 "$(agent_prompt_calls "$other")" "blocked $other got no prompt"
    no_state_file "$other.ask-start" || t_fail "blocked $other wrote an ask-start"
  done
}

case_worker_exclusivity_active_scouts() {
  local root
  root="$(git rev-parse --show-toplevel)"
  mkdir -p "$CASE_TMP/driver"
  hd_run spawn d1 scout --cwd "$CASE_TMP/driver"
  assert_eq 0 "$HD_RC" "hd spawn d1"
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "hd spawn s1"
  hd_run spawn s2 scout
  assert_eq 0 "$HD_RC" "hd spawn s2"
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  d1-*)
    rc=0
    "$HD" ask s1 'Read src/a.txt.' > "$FAKE_DIR/s1.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/s1.rc"
    rc=0
    "$HD" ask s2 'Read src/a.txt.' > "$FAKE_DIR/s2.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/s2.rc"
    "$HD" ask w2 'Do the work.' > "$FAKE_DIR/w2.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/w2.rc"
    printf 'timeout waiting\n'
    exit 1 ;;
  s1-*|s2-*) printf 'timeout waiting\n'; exit 1 ;;
esac
turn "$2" "STATUS: done"
EOF
  hd_run ask d1 'Drive the checks.'
  assert_eq 0 "$HD_RC" "driver ask"
  assert_eq 0 "$(cat "$FAKE_DIR/s1.rc")" "active s1 ask"
  assert_eq 0 "$(cat "$FAKE_DIR/s2.rc")" "active s2 ask"
  assert_eq 1 "$(cat "$FAKE_DIR/w2.rc")" "worker blocked by scouts"
  assert_contains "$(cat "$FAKE_DIR/w2.out")" "hd: cannot ask worker w2: active ask in $root (s1 (scout), s2 (scout)); wait for it to finish, or run w2 in its own git worktree (--cwd)" "joined blockers"
  assert_eq 0 "$(agent_prompt_calls w2)" "blocked worker got no prompt"
  no_state_file w2.ask-start || t_fail "blocked worker wrote an ask-start"
}

case_workers_in_separate_worktrees() {
  git worktree add -q "$CASE_TMP/wt2" -b wt2
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  hd_run spawn w2 worker --cwd "$CASE_TMP/wt2"
  assert_eq 0 "$HD_RC" "hd spawn w2 in its own worktree"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  w1-*)
    rc=0
    "$HD" ask w2 $'Do the work.\n\nCheck: `bash tests/check.sh`\nScope: `src/impl.txt`' > "$FAKE_DIR/w2.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$FAKE_DIR/w2.rc"
    turn "$2" "STATUS: done" ;;
  w2-*)
    wt="$(dirname "$FAKE_DIR")/wt2"
    mkdir -p "$wt/tests"
    printf 'hello\n' > "$wt/src/impl.txt"
    printf 'grep -q hello src/impl.txt\n' > "$wt/tests/check.sh"
    turn "$2" "STATUS: done" ;;
esac
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "hd ask w1"
  assert_eq 0 "$(cat "$FAKE_DIR/w2.rc")" "hd ask w2 in its worktree"
  assert_not_contains "$HD_OUT" '--- concurrent' "w1 has no concurrent ask"
  assert_not_contains "$(cat "$FAKE_DIR/w2.out")" '--- concurrent' "w2 has no concurrent ask"
  assert_contains "$(cat "$FAKE_DIR/w2.out")" '--- red: Check exit=' "w2 red gate"
  assert_jq '.concurrent == []' "$(journal_entry w1)" "w1 journal"
  assert_jq '.concurrent == []' "$(journal_entry w2)" "w2 journal"
  assert_eq hello "$(cat "$CASE_TMP/wt2/src/impl.txt")" "w2 implementation in its worktree"
}

case_stop_closes_open_ask() {
  spawn_w1
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  w1-*) printf 'timeout waiting\n'; exit 1 ;;
esac
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "w1 times out"
  assert_contains "$HD_OUT" 'STATUS: still_working' "w1 still working"
  assert_exists "$(state_file w1.ask-start)" "w1 ask is open"
  no_state_file w1.ask-end || t_fail "w1 ask ended on timeout"

  hd_run stop w1
  assert_eq 0 "$HD_RC" "hd stop w1"
  assert_exists "$(state_file w1.ask-end)" "stop closed the ask"

  hd_run ask w2 'Do it.'
  assert_eq 0 "$HD_RC" "worker in the same tree after stop"
}

case_failed_dispatch_closes_open_ask() {
  spawn_w1
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  w1-*)
    printf 'boom\n' >&2
    exit 1 ;;
esac
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  [[ "$HD_RC" != 0 ]] || t_fail "failed dispatch exited 0"
  assert_contains "$HD_OUT" 'boom' "dispatch error"
  assert_exists "$(state_file w1.ask-end)" "failed dispatch closed the ask"

  hd_run ask w2 'Do it.'
  assert_eq 0 "$HD_RC" "worker in the same tree after failure"
}

case_dead_agent_stale_ask() {
  spawn_w1
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  w1-*) printf 'timeout waiting\n'; exit 1 ;;
  w2-*)
    if (( $3 == 1 )); then
      mkdir -p tests
      printf 'hello\n' > src/impl.txt
      printf 'grep -q hello src/impl.txt\n' > tests/check.sh
      printf 'outside\n' > outside.txt
    fi
    turn "$2" "STATUS: done" ;;
esac
EOF
  hd_run ask w1 'Do the work.'
  assert_eq 0 "$HD_RC" "w1 times out"
  local dead
  dead="$(find "$FAKE_DIR/agents" -maxdepth 1 -type d -name 'w1-*' -print -quit)"
  [[ -n "$dead" ]] || t_fail "no fake agent for w1"
  rm -rf "$dead"
  no_state_file w1.ask-end || t_fail "stale w1 ask has an end marker"

  hd_run ask w2 $'Do the work.\n\nCheck: `bash tests/check.sh`\nScope: `src/impl.txt`'
  assert_eq 0 "$HD_RC" "worker after a dead agent's stale ask"
  assert_not_contains "$HD_OUT" '--- concurrent' "dead agent is not concurrent"
  assert_jq '.concurrent == []' "$(journal_entry w2)" "w2 journal"
  assert_contains "$HD_OUT" '--- autofix 1/2: outside Scope: outside.txt' "Scope gate stays active"
  assert_contains "$HD_OUT" '--- red: Check exit=' "red gate stays active"
}

case_skill_worktree_parallelism_docs() {
  assert_file_contains "$ROOT/SKILL.md" 'git worktree add' "worktree recipe"
  assert_file_contains "$ROOT/SKILL.md" 'herdr worktree create' "worktree recipe"
  assert_file_contains "$ROOT/SKILL.md" 'hd spawn <name> worker --cwd <dir>' "worker spawn recipe"
  assert_file_contains "$ROOT/SKILL.md" 'at most one worker per worktree' "worker exclusivity"
  assert_file_contains "$ROOT/SKILL.md" '`hd ask` refuses a worker while another ask is active in the same git worktree' "ask refusal"
  assert_file_contains "$ROOT/SKILL.md" 'parallel read-only asks in the same tree appear under `--- concurrent`' "updated Limits"
  assert_contains "$(sed -n '50p' "$ROOT/SKILL.md")" 'ballooning context' "line 50 unchanged"
}

case_check_pipefail() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "need a decision
STATUS: needs_decision"
EOF
  local brief='Do the work.

Check: `false | cat`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "exit=1"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
  assert_not_contains "$HD_OUT" "--- autofix"
}

case_autofix_check_fixed() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  turn "$2" "first try
STATUS: done"
else
  mkdir -p src
  printf 'b\n' > src/b.txt
  turn "$2" "fixed
STATUS: done"
fi
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: check exit=1"
  assert_contains "$HD_OUT" "fixed"
  assert_contains "$HD_OUT" "exit=0"
  assert_not_contains "$HD_OUT" "first try"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
  local prompt
  prompt="$(cat "$(single_agent_dir)/last-prompt")"
  assert_contains "$prompt" 'Check `test -f src/b.txt` exited 1' "autofix prompt"
  assert_contains "$prompt" "OUTPUT_FILE" "autofix prompt"
}

case_autofix_cap() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "still broken
STATUS: done"
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_eq 3 "$(prompt_calls)" "agent prompt calls"
  assert_contains "$HD_OUT" "--- autofix 2/2: check exit=1"
  assert_contains "$HD_OUT" "exit=1"
  assert_not_contains "$HD_OUT" "--- autofix 3"
}

case_autofix_russian_status() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  turn "$2" "не вышло
СТАТУС: готово"
else
  mkdir -p src
  printf 'b\n' > src/b.txt
  turn "$2" "исправил
СТАТУС: готово"
fi
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
  assert_contains "$HD_OUT" "exit=0"
}

case_autofix_scope_outside() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  mkdir -p src
  printf 'b\n' > src/b.txt
  printf 'other\n' > other.txt
else
  rm -f other.txt
fi
turn "$2" "did it
STATUS: done"
EOF
  local brief='Do the work.

Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: outside Scope: other.txt"
  assert_contains "$HD_OUT" "--- scope: 1 changed, 0 outside Scope"
  local prompt
  prompt="$(cat "$(single_agent_dir)/last-prompt")"
  assert_contains "$prompt" "other.txt" "autofix prompt"
}

case_autofix_journal() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  turn "$2" "first try
STATUS: done"
else
  mkdir -p src
  printf 'b\n' > src/b.txt
  turn "$2" "fixed
STATUS: done"
fi
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl" entry
  assert_eq 1 "$(( $(wc -l < "$journal") ))" "journal line count"
  entry="$(jq -c 'select(.event == "ask")' "$journal")"
  assert_jq '.autofix == 1' "$entry" "journal autofix"
  assert_eq "$(git rev-parse HEAD)" "$(jq -r '.head' <<< "$entry")" "journal head"
  assert_jq '.base | length > 0' "$entry" "journal base"
  write_hook <<'EOF2'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "did it
STATUS: done"
EOF2
  hd_run ask w1 'Do the work.

Check: `test -f src/b.txt`'
  assert_eq 0 "$HD_RC" "hd ask without autofix"
  entry="$(jq -c 'select(.event == "ask")' "$journal" | tail -n 1)"
  assert_jq '.autofix == 0' "$entry" "journal autofix without rounds"
}

case_no_autofix_failed_status() {
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "broken
STATUS: failed"
EOF
  local brief='Do the work.

Check: `test -f src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
  assert_not_contains "$HD_OUT" "--- autofix"
}

case_ask_codex_hook_review() {
  hd_run spawn sc scout --agent codex
  assert_eq 0 "$HD_RC" "hd spawn codex scout"
  mkdir -p "$FAKE_DIR/panes/p1"
  printf '%s\n' '⚠ 1 hook needs review before it can run.' '  t trust all · enter review · esc close' > "$FAKE_DIR/panes/p1/screen"
  hd_run ask sc 'Read the code.'
  assert_contains "$HD_OUT" "STATUS: blocked_ui"
  assert_contains "$HD_OUT" "hook needs review"
  assert_contains "$HD_OUT" "t trust all · enter review · esc close"
  assert_eq 0 "$HD_RC" "hd ask"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
  [[ ! -e "$XDG_CACHE_HOME/herdr-delegate/journal.jsonl" ]] || t_fail "blocked ask wrote a journal entry"
}

case_ask_codex_folder_trust() {
  hd_run spawn sc scout --agent codex
  assert_eq 0 "$HD_RC" "hd spawn codex scout"
  mkdir -p "$FAKE_DIR/panes/p1"
  printf '%s\n' 'Trust this folder?' > "$FAKE_DIR/panes/p1/screen"
  hd_run ask sc 'Read the code.'
  assert_contains "$HD_OUT" "STATUS: blocked_ui"
  assert_contains "$HD_OUT" "Trust this folder?"
  assert_eq 0 "$(prompt_calls)" "agent prompt calls"
}

case_ask_pi_ignores_folder_trust() {
  hd_run spawn w1 worker --agent pi
  assert_eq 0 "$HD_RC" "hd spawn pi worker"
  mkdir -p "$FAKE_DIR/panes/p1"
  printf '%s\n' 'Trust this folder?' > "$FAKE_DIR/panes/p1/screen"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "STATUS: done"
EOF
  hd_run ask w1 'Do the work.'
  assert_not_contains "$HD_OUT" "blocked_ui"
  assert_contains "$HD_OUT" "STATUS: done"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

setup_claims() {
  local role="${1:-scout}"
  seq -f 'l%g' 1 10 > src/a.txt
  hd_run spawn w1 "$role"
  assert_eq 0 "$HD_RC" "hd spawn w1"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
if [[ "$3" == 1 ]]; then
  payload="$(payload_path "$1")"
  printf '%s\n' "$payload" > "$FAKE_DIR/$1.payload"
  printf '%s\n' "$CLAIMS_FIRST" > "$payload"
elif [[ -v CLAIMS_NEXT ]]; then
  printf '%s\n' "$CLAIMS_NEXT" > "$(cat "$FAKE_DIR/$1.payload")"
fi
turn "$2" 'STATUS: done'
EOF
}

case_claims_c1() {
  setup_claims
  CLAIMS_FIRST='- `src/a.txt:5` — `l5`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found; 0 absent, 0 found in repo"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c2() {
  setup_claims
  CLAIMS_FIRST='- `src/a.txt:2` — `l9`' CLAIMS_NEXT='- `src/a.txt:9` — `l9`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 1 not found"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found"
  local prompt="$(single_agent_dir)/last-prompt"
  assert_file_contains "$prompt" "src/a.txt:2"
  assert_file_contains "$prompt" "not within 3 lines"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c3() {
  setup_claims
  CLAIMS_FIRST='`src/a.txt:2` — `l5`
`src/a.txt:2–3` — `l6`
`src/missing.txt:1` — `x`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 3 cited, 1 not found; 0 absent, 0 found in repo"
  assert_contains "$HD_OUT" 'src/missing.txt:1 `x`: no such file'
  assert_contains "$HD_OUT" "--- autofix 2/2: claims: 1 not found"
  assert_eq 3 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c4() {
  setup_claims
  mkdir -p tests
  printf 'callFoo()\n' > tests/x_test.go
  git add tests/x_test.go
  CLAIMS_FIRST='ABSENT: `callFoo(`' CLAIMS_NEXT='callFoo( occurs in tests/x_test.go:1, a test' hd_run ask w1 'Find callFoo.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 1 absent found"
  assert_file_contains "$(single_agent_dir)/last-prompt" "tests/x_test.go:1"
  assert_contains "$HD_OUT" "--- claims: 0 cited, 0 not found; 0 absent, 0 found in repo"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c5() {
  setup_claims
  printf 'neverThere\n' > src/untracked.txt
  CLAIMS_FIRST='ABSENT: `neverThere`' hd_run ask w1 'Find neverThere.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_contains "$HD_OUT" "--- claims: 0 cited, 0 not found; 1 absent, 0 found in repo"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c6() {
  setup_claims worker
  CLAIMS_FIRST='- `src/a.txt:2` — `l9`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_not_contains "$HD_OUT" "--- claims"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_c7() {
  setup_claims
  CLAIMS_FIRST='- `src/a.txt:5` — `l5`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_jq '.claims == {"cited":1,"bad":0,"absent":0,"found":0}' "$(tail -n 1 "$journal")" "scout journal"
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  CLAIMS_FIRST='- `src/a.txt:2` — `l9`' hd_run ask w2 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_jq 'has("claims") and .claims == null' "$(tail -n 1 "$journal")" "worker journal"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" 'STATUS: done'
EOF
  hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask without payload"
  assert_not_contains "$HD_OUT" "--- claims"
  assert_jq 'has("claims") and .claims == null' "$(tail -n 1 "$journal")" "scout journal without payload"
}

run_case ask_codex_hook_review case_ask_codex_hook_review
run_case ask_codex_folder_trust case_ask_codex_folder_trust
run_case ask_pi_ignores_folder_trust case_ask_pi_ignores_folder_trust
run_case ask_check_pipefail case_check_pipefail
run_case ask_autofix_check_fixed case_autofix_check_fixed
run_case ask_autofix_cap case_autofix_cap
run_case ask_autofix_russian_status case_autofix_russian_status
run_case ask_autofix_scope_outside case_autofix_scope_outside
run_case ask_autofix_journal case_autofix_journal
run_case ask_no_autofix_failed_status case_no_autofix_failed_status
run_case ask_reply_check_scope case_reply_check_scope
run_case ask_scope_outside_file case_scope_outside_file
run_case ask_scope_directory_and_glob case_scope_directory_and_glob
run_case ask_journal_line case_journal_ask_line
run_case ask_diff_ignores_pre_dirty_file case_diff_ignores_pre_dirty_file
run_case ask_prompt_output_file case_prompt_output_file
run_case ask_spawns_sidekick case_ask_spawns_sidekick
run_case ask_scope_in_repo_without_index case_scope_in_repo_without_index
run_case ask_check_gtimeout_fallback case_check_gtimeout_fallback
run_case ask_check_without_timeout case_check_without_timeout
run_case ask_without_timeout_no_check case_ask_without_timeout_no_check
run_case ask_check_without_backticks case_check_without_backticks
run_case ask_concurrent case_concurrent_ask
run_case ask_worker_exclusivity_active_worker case_worker_exclusivity_same_tree
run_case ask_worker_exclusivity_active_scouts case_worker_exclusivity_active_scouts
run_case ask_workers_separate_worktrees case_workers_in_separate_worktrees
run_case ask_stop_closes_open_ask case_stop_closes_open_ask
run_case ask_failed_dispatch_closes_ask case_failed_dispatch_closes_open_ask
run_case ask_dead_agent_stale_marker case_dead_agent_stale_ask
run_case ask_skill_worktree_docs case_skill_worktree_parallelism_docs
case_claims_multiline_quote() {
  setup_claims
  printf 'foo(\n  "bar")\n' > src/m.txt
  CLAIMS_FIRST='- `src/m.txt:1-2` — `foo("bar")`' hd_run ask w1 'Read src/m.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_line_ref_quote() {
  setup_claims
  CLAIMS_FIRST='- `src/a.txt:5` — `:6`' hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 0 cited, 0 not found"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

commit_old_version() {
  printf 'old1\nold2\nold3\n' > src/old.txt
  git add src/old.txt
  git -c user.name=test -c user.email=test@example.com commit -qm old
  git -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m after
  git tag old-tag HEAD~1
}

case_claims_git_ref() {
  setup_claims
  commit_old_version
  rm src/old.txt
  CLAIMS_FIRST='- `HEAD~1:src/old.txt:2` — `old2`' hd_run ask w1 'Read src/old.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found; 0 absent, 0 found in repo"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_git_tag_ref() {
  setup_claims
  commit_old_version
  rm src/old.txt
  CLAIMS_FIRST='- `old-tag:./src/old.txt:3` — `old3`' hd_run ask w1 'Read src/old.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found; 0 absent, 0 found in repo"
  assert_not_contains "$HD_OUT" "--- autofix"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_git_ref_errors() {
  setup_claims
  commit_old_version
  rm src/old.txt
  CLAIMS_FIRST=$'- `HEAD~1:src/old.txt:2` — `l9`\n- `nosuchref:src/old.txt:1` — `old1`\n- `HEAD~1:src:1` — `x`' hd_run ask w1 'Read src/old.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 3 not found"
  assert_contains "$HD_OUT" "--- claims: 3 cited, 3 not found; 0 absent, 0 found in repo"
  assert_contains "$HD_OUT" 'HEAD~1:src/old.txt:2 `l9`: not within 3 lines'
  assert_contains "$HD_OUT" 'nosuchref:src/old.txt:1 `old1`: no such file'
  assert_contains "$HD_OUT" 'HEAD~1:src:1 `x`: no such file'
  assert_eq 3 "$(prompt_calls)" "agent prompt calls"
}

case_claims_mass_missing_bailout() {
  setup_claims
  local lines="" i
  for i in $(seq 1 20); do lines+="- \`src/m$i.txt:1\` — \`x\`"$'\n'; done
  CLAIMS_FIRST="${lines%$'\n'}" hd_run ask w1 'Find the modules.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix skipped: claims: 20/20 citations have no such file (likely wrong ref, path prefix, or cwd)"
  assert_not_contains "$HD_OUT" "--- autofix 1/2"
  assert_contains "$HD_OUT" "--- claims: 20 cited, 20 not found"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_autofix_cap() {
  setup_claims
  local lines="" i prompt count
  for i in $(seq 1 25); do lines+="- \`src/a.txt:1\` — \`l10\`"$'\n'; done
  CLAIMS_FIRST="${lines%$'\n'}" hd_run ask w1 'Read src/a.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 25 not found"
  prompt="$(<"$(single_agent_dir)/last-prompt")"
  assert_contains "$prompt" "...and 5 more not shown" "autofix cap marker"
  count="$(grep -c 'not within 3 lines' <<< "$prompt")"
  assert_eq 20 "$count" "citation error lines in the autofix prompt"
}

case_claims_found_autofix_cap() {
  setup_claims
  local lines="" i prompt count
  for i in $(seq 1 25); do printf 'needle%s\n' "$i"; done > src/strings.txt
  git add src/strings.txt
  for i in $(seq 1 25); do lines+="ABSENT: \`needle$i\`"$'\n'; done
  CLAIMS_FIRST="${lines%$'\n'}" hd_run ask w1 'Find the needles.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- autofix 1/2: claims: 25 absent found"
  prompt="$(<"$(single_agent_dir)/last-prompt")"
  assert_contains "$prompt" "...and 5 more not shown" "found cap marker"
  count="$(grep -c 'ABSENT `needle' <<< "$prompt")"
  assert_eq 20 "$count" "found error lines in the autofix prompt"
}

case_claims_git_ref_large_blob() {
  setup_claims
  {
    printf 'first\nlarge-target-line\n'
    awk 'BEGIN { for (i = 0; i < 4000; i++) printf "padding-line-%04d-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", i }'
  } > src/big.txt
  git add src/big.txt
  git -c user.name=test -c user.email=test@example.com commit -qm big
  git -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m after
  rm src/big.txt
  CLAIMS_FIRST='- `HEAD~1:src/big.txt:2` — `large-target-line`' hd_run ask w1 'Read src/big.txt.'
  assert_eq 0 "$HD_RC" "hd ask"
  assert_contains "$HD_OUT" "--- claims: 1 cited, 0 not found; 0 absent, 0 found in repo"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_claims_bad_and_found_no_leak() {
  setup_claims
  printf 'foundNeedle\n' > src/needle.txt
  git add src/needle.txt
  CLAIMS_FIRST=$'- `src/a.txt:1` — `l10`\nABSENT: `foundNeedle`' hd_run ask w1 'Check both.'
  assert_eq 0 "$HD_RC" "hd ask"
  local prompt bad_section
  prompt="$(<"$(single_agent_dir)/last-prompt")"
  bad_section="$(awk '/These citations in OUTPUT_FILE/{flag=1;next}/These ABSENT strings/{flag=0}flag' <<< "$prompt")"
  assert_contains "$bad_section" "src/a.txt:1" "bad section has citation"
  assert_not_contains "$bad_section" "ABSENT" "bad section does not leak found lines"
}

run_case ask_claims_multiline_quote case_claims_multiline_quote
run_case ask_claims_line_ref_quote case_claims_line_ref_quote
run_case ask_claims_git_ref case_claims_git_ref
run_case ask_claims_git_tag_ref case_claims_git_tag_ref
run_case ask_claims_git_ref_errors case_claims_git_ref_errors
run_case ask_claims_git_ref_large_blob case_claims_git_ref_large_blob
run_case ask_claims_bad_and_found_no_leak case_claims_bad_and_found_no_leak
run_case ask_claims_mass_missing_bailout case_claims_mass_missing_bailout
run_case ask_claims_autofix_cap case_claims_autofix_cap
run_case ask_claims_found_autofix_cap case_claims_found_autofix_cap
run_case ask_claims_c1 case_claims_c1
run_case ask_claims_c2 case_claims_c2
run_case ask_claims_c3 case_claims_c3
run_case ask_claims_c4 case_claims_c4
run_case ask_claims_c5 case_claims_c5
run_case ask_claims_c6 case_claims_c6
run_case ask_claims_c7 case_claims_c7
run_case ask_claims_reviewer case_claims_reviewer
run_case ask_claims_reviewer_no_findings case_claims_reviewer_no_findings
run_case ask_claims_reviewer_absent case_claims_reviewer_absent
run_case ask_scope_reviewer_without_scope case_scope_reviewer_without_scope
run_case ask_autofix_scope_reviewer case_autofix_scope_reviewer
run_case ask_scope_worker_without_scope case_scope_worker_without_scope
run_case ask_scope_scout_without_scope case_scope_scout_without_scope
write_red_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p tests
if [[ "${RED_TEST_ONLY:-}" != 1 ]]; then
  printf 'hello\n' > src/impl.txt
fi
if [[ "${RED_EXTRA:-}" == 1 ]]; then
  mkdir -p e2e docs
  printf 'spec\n' > e2e/flow.e2e-spec.ts
  printf 'notes\n' > docs/notes.md
fi
if [[ "${RED_FIRST_PASS:-}" == 1 && "$3" == 1 || "${RED_TEST_ONLY:-}" == 1 ]]; then
  printf 'true\n' > tests/check.sh
else
  printf 'grep -q hello src/impl.txt\n' > tests/check.sh
fi
turn "$2" "STATUS: ${RED_STATUS:-done}"
EOF
}

ask_red() {
  hd_run ask w1 $'Do the work.\n\nCheck: `bash tests/check.sh`'"$1"
  assert_eq 0 "$HD_RC" "hd ask"
}

case_red_added() {
  spawn_w1
  write_red_hook
  ask_red ""
  assert_contains "$HD_OUT" "--- red: Check exit=2 with 1 implementation files"
  assert_after "$HD_OUT" "--- check: bash tests/check.sh" "exit=0"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
  assert_eq hello "$(cat src/impl.txt)" "restored implementation"
  [[ ! -e "$XDG_CACHE_HOME/herdr-delegate/test_p0/w1.red" ]] || t_fail "red backup remains"
}

case_red_autofix() {
  spawn_w1
  export RED_FIRST_PASS=1
  write_red_hook
  ask_red ""
  assert_contains "$HD_OUT" "--- autofix 1/2: red: tests pass without the implementation"
  assert_contains "$HD_OUT" "--- red: Check exit=2"
  assert_file_contains "$(single_agent_dir)/last-prompt" "src/impl.txt"
  assert_eq 2 "$(prompt_calls)" "agent prompt calls"
}

case_red_modified() {
  printf 'old\n' > src/impl.txt
  git add src/impl.txt
  git -c user.name=test -c user.email=test@example.com commit -qm implementation
  spawn_w1
  write_red_hook
  ask_red ""
  assert_contains "$HD_OUT" "--- red: Check exit=1 with 1 implementation files"
  assert_eq hello "$(cat src/impl.txt)" "restored implementation"
}

case_red_skip() {
  spawn_w1
  export RED_FIRST_PASS=1
  write_red_hook
  ask_red $'\nRed: skip'
  assert_not_contains "$HD_OUT" "--- red"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
}

case_red_test_only() {
  spawn_w1
  export RED_TEST_ONLY=1
  write_red_hook
  ask_red ""
  assert_not_contains "$HD_OUT" "--- red"
}

case_red_e2e_spec_and_docs() {
  spawn_w1
  export RED_EXTRA=1
  write_red_hook
  ask_red ""
  assert_contains "$HD_OUT" "--- red: Check exit=2 with 1 implementation files"
}

case_red_tests_and_docs_only() {
  spawn_w1
  export RED_TEST_ONLY=1 RED_EXTRA=1
  write_red_hook
  ask_red ""
  assert_not_contains "$HD_OUT" "--- red"
}

case_red_failed_status() {
  spawn_w1
  export RED_STATUS=failed
  write_red_hook
  ask_red ""
  assert_not_contains "$HD_OUT" "--- red"
}

case_red_interrupted() {
  spawn_w1
  local red="$XDG_CACHE_HOME/herdr-delegate/test_p0/w1.red"
  mkdir -p "$red/files/src"
  printf 'modified\tsrc/impl.txt\n' > "$red/list"
  printf 'saved\n' > "$red/files/src/impl.txt"
  printf 'base\n' > src/impl.txt
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p tests
printf 'true\n' > tests/check.sh
cp src/impl.txt src/seen.txt
turn "$2" "STATUS: failed"
EOF
  ask_red ""
  assert_contains "$HD_OUT" "hd: restored 1 files from an interrupted red run"
  assert_eq saved "$(cat src/seen.txt)" "implementation seen by worker"
}

case_red_error() {
  printf 'old\n' > src/impl.txt
  git add src/impl.txt
  git -c user.name=test -c user.email=test@example.com commit -qm implementation
  spawn_w1
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p tests
printf 'true\n' > tests/check.sh
rm src/impl.txt
mkdir src/impl.txt
printf 'x\n' > src/impl.txt/a
turn "$2" "STATUS: done"
EOF
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  ask_red ""
  assert_contains "$HD_OUT" "STATUS: done"
  assert_contains "$HD_OUT" "--- red: error exit=1"
  assert_contains "$HD_OUT" "cannot revert directory src/impl.txt as a file"
  assert_eq 1 "$(prompt_calls)" "agent prompt calls"
  assert_eq x "$(cat src/impl.txt/a)" "worker tree kept"
  assert_jq '.red_exit == null' "$(tail -n 1 "$journal")"
}

case_red_journal() {
  spawn_w1
  write_red_hook
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  ask_red ""
  assert_jq '.red_exit == 2' "$(tail -n 1 "$journal")"
  export RED_TEST_ONLY=1
  rm tests/check.sh
  ask_red ""
  assert_jq 'has("red_exit") and .red_exit == null' "$(tail -n 1 "$journal")"
}

run_case ask_red_added case_red_added
run_case ask_red_autofix case_red_autofix
run_case ask_red_modified case_red_modified
run_case ask_red_skip case_red_skip
run_case ask_red_test_only case_red_test_only
run_case ask_red_e2e_spec_and_docs case_red_e2e_spec_and_docs
run_case ask_red_tests_and_docs_only case_red_tests_and_docs_only
run_case ask_red_failed_status case_red_failed_status
run_case ask_red_interrupted case_red_interrupted
run_case ask_red_journal case_red_journal
run_case ask_red_error case_red_error
