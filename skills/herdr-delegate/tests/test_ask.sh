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
