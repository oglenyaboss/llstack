#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_model_thinking() {
  export HD_MODEL=prov/m1
  export HD_THINKING=high
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn"
  assert_calls_nonempty
  local dir args
  dir="$(single_agent_dir)"
  args="$dir/start.args"
  assert_file_contains "$args" "--model prov/m1"
  assert_file_contains "$args" "--thinking high"
  assert_file_contains "$args" "--kind pi"
  assert_file_contains "$args" "--append-system-prompt $ROOT/roles/worker.md"
  assert_file_contains "$args" "--append-system-prompt $ROOT/roles/_envelope.md"
  assert_file_contains "$args" "--tools read,grep,find,ls,bash,edit,write,tool_search"
}

case_no_model_thinking() {
  unset HD_MODEL HD_THINKING
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn"
  assert_calls_nonempty
  local dir args
  dir="$(single_agent_dir)"
  args="$dir/start.args"
  assert_file_not_contains "$args" "--model"
  assert_file_not_contains "$args" "--thinking"
}

case_extensions_and_scout() {
  export HD_PI_EXTENSIONS=/x/a.ts:/x/b.ts
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  local dir args
  dir="$(single_agent_dir)"
  args="$dir/start.args"
  assert_file_contains "$args" "-e /x/a.ts"
  assert_file_contains "$args" "-e /x/b.ts"

  hd_run spawn sc scout
  assert_eq 0 "$HD_RC" "hd spawn sc"
  assert_calls_nonempty
  local scout_args="" tools
  for args in "$FAKE_DIR"/agents/*/start.args; do
    if grep -qF "roles/scout.md" "$args"; then scout_args="$args"; fi
  done
  [[ -n "$scout_args" ]] || t_fail "no agent start args for scout"
  tools="$(sed -n 's/.*--tools \([^ ]*\).*/\1/p' "$scout_args")"
  [[ -n "$tools" ]] || t_fail "scout start has no --tools value"
  assert_not_contains "$tools" "edit" "scout tools"
  assert_contains "$tools" "write" "scout tools"
}

case_missing_cwd() {
  set +e
  HD_OUT="$("$TIMEOUT" 10 "$HD" spawn w1 worker --cwd "$PWD/missing" 2>&1)"
  HD_RC=$?
  set -e
  assert_eq 1 "$HD_RC" "hd spawn with a missing cwd"
  assert_contains "$HD_OUT" "no such directory"
}

case_md5_fallback() {
  local fake_md5="$CASE_TMP/fake-md5"
  mkdir -p "$fake_md5"
  cat > "$fake_md5/md5" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-q" ]] || exit 2
cat >/dev/null
printf 'abcd1234ffffffffffffffffffffffff\n'
EOF
  chmod +x "$fake_md5/md5"
  export PATH="$fake_md5:$(path_without md5sum)"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn without md5sum"
  assert_exists "$FAKE_DIR/agents/w1-abcd" "agent named with the md5 fallback tag"
}

run_case spawn_model_and_thinking case_model_thinking
run_case spawn_without_model_and_thinking case_no_model_thinking
run_case spawn_extensions_and_scout case_extensions_and_scout
run_case spawn_missing_cwd case_missing_cwd
run_case spawn_md5_fallback case_md5_fallback
