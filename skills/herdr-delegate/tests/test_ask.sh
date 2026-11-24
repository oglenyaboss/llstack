#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

spawn_w1() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_calls_nonempty
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
  spawn_w1
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn w2"
  mkdir -p "$CASE_TMP/elsewhere"
  hd_run spawn w3 worker --cwd "$CASE_TMP/elsewhere"
  assert_eq 0 "$HD_RC" "hd spawn w3"
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
case "$1" in
  w1-*)
    "$HD" ask w2 'Other work.' > "$FAKE_DIR/w2.out"
    mkdir -p src
    printf 'b\n' > src/b.txt ;;
  w2-*) printf 'other\n' > other.txt ;;
esac
turn "$2" "did it
STATUS: done"
EOF
  hd_run ask w3 'Before.'
  assert_eq 0 "$HD_RC" "hd ask w3"
  sleep 1
  hd_run ask w1 $'Do the work.\n\nScope: `src/b.txt`'
  assert_eq 0 "$HD_RC" "hd ask w1"
  assert_contains "$HD_OUT" '--- concurrent: w2 ' "w1 names w2"
  assert_contains "$(cat "$FAKE_DIR/w2.out")" '--- concurrent: w1 ' "w2 names w1"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl"
  assert_jq '.concurrent == ["w2"]' "$(jq -c 'select(.name == "w1")' "$journal")" "w1 journal"
  assert_jq '.concurrent == []' "$(jq -c 'select(.name == "w3")' "$journal")" "w3 journal"
  sleep 1
  hd_run ask w2 'After.'
  assert_eq 0 "$HD_RC" "hd ask w2 after"
  assert_not_contains "$HD_OUT" '--- concurrent' "sequential ask"
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

run_case ask_claims_multiline_quote case_claims_multiline_quote
run_case ask_claims_line_ref_quote case_claims_line_ref_quote
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
write_red_hook() {
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
mkdir -p tests
if [[ "${RED_TEST_ONLY:-}" != 1 ]]; then
  printf 'hello\n' > src/impl.txt
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
run_case ask_red_failed_status case_red_failed_status
run_case ask_red_interrupted case_red_interrupted
run_case ask_red_journal case_red_journal
run_case ask_red_error case_red_error
