#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

start_args() {
  local files=("$FAKE_DIR"/agents/"$1"-*/start.args)
  [[ -e "${files[0]}" ]] || t_fail "no start args for $1"
  printf '%s\n' "${files[0]}"
}

pane_calls() {
  [[ -f "$FAKE_DIR/calls.log" ]] || { printf '0\n'; return; }
  grep -c -E $'^(pane\t(split|run)|tab\tcreate)' "$FAKE_DIR/calls.log" || true
}

run_dir_entry() {
  local file
  file="$(find "$XDG_CACHE_HOME/herdr-delegate" -name "$1" -print -quit)"
  [[ -n "$file" ]] || t_fail "no run dir entry $1"
  printf '%s\n' "$file"
}

case_model_thinking() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1","thinking":"high"}}'
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

case_no_model() {
  hd_config '{"default":{"harness":"pi"}}'
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn without a model"
  assert_contains "$HD_OUT" "worker" "slot in the message"
  assert_contains "$HD_OUT" "$HD_CONFIG" "config path in the message"
  assert_eq 0 "$(pane_calls)" "panes after a missing model"
  [[ ! -e "$FAKE_DIR/agents" ]] || t_fail "an agent started without a model"
}

case_no_harness() {
  hd_config '{"default":{"model":"prov/m1"}}'
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn without a harness"
  assert_contains "$HD_OUT" "worker" "slot in the message"
  assert_contains "$HD_OUT" "harness" "missing harness message"
  assert_eq 0 "$(pane_calls)" "panes after a missing harness"
}

case_env_refused() {
  export HD_MODEL=prov/m1
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with HD_MODEL set"
  assert_contains "$HD_OUT" "HD_MODEL" "variable in the message"
  assert_contains "$HD_OUT" "$HD_CONFIG" "config path in the message"
  assert_eq 0 "$(pane_calls)" "panes after an env refusal"
}

case_bad_json() {
  printf '{\n' > "$HD_CONFIG"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with invalid JSON"
  assert_contains "$HD_OUT" "$HD_CONFIG" "config path in the message"
  assert_eq 0 "$(pane_calls)" "panes after invalid JSON"
}

case_config_two_values() {
  printf '{"default":{"harness":"pi","model":"prov/m1"}}\nnull\n' > "$HD_CONFIG"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with two top-level values"
  assert_contains "$HD_OUT" "$HD_CONFIG" "config path in the message"
  assert_contains "$HD_OUT" "is not valid JSON" "two top-level values"
  assert_eq 0 "$(pane_calls)" "panes after two top-level values"
}

case_config_empty() {
  : > "$HD_CONFIG"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with an empty config"
  assert_contains "$HD_OUT" "is not valid JSON" "empty config"
  assert_eq 0 "$(pane_calls)" "panes after an empty config"
}

case_missing_config() {
  export HD_CONFIG="$CASE_TMP/missing-config.json"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn without a config file"
  assert_contains "$HD_OUT" "$CASE_TMP/missing-config.json" "config path in the message"
  assert_eq 0 "$(pane_calls)" "panes after a missing config"
}

case_hd_config_path() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  printf '{"default":{"harness":"pi","model":"prov/m1"}}\n' > "$CASE_TMP/first-config.json"
  printf '{"default":{"harness":"pi","model":"prov/m2"}}\n' > "$CASE_TMP/second-config.json"
  export HD_CONFIG="$CASE_TMP/second-config.json"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn with HD_CONFIG"
  assert_file_contains "$(start_args w1)" "--model prov/m2" "model from HD_CONFIG"
}

case_unknown_slot() {
  hd_run spawn x nosuch
  assert_eq 1 "$HD_RC" "hd spawn with an unknown slot"
  assert_contains "$HD_OUT" "unknown slot" "unknown slot message"
  assert_contains "$HD_OUT" "nosuch" "unknown slot message"
  assert_eq 0 "$(pane_calls)" "panes after an unknown slot"
}

case_slot_model() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"model":"prov/m2"}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1 worker"
  assert_file_contains "$(start_args w1)" "--model prov/m2" "worker model"
  hd_run spawn s1 scout
  assert_eq 0 "$HD_RC" "hd spawn s1 scout"
  assert_file_contains "$(start_args s1)" "--model prov/m1" "scout model"
}

case_slot_harness() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"harness":"codex","model":"gpt-x"}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1 worker on codex"
  assert_file_contains "$(start_args w1)" "--kind codex" "codex harness"
  assert_file_contains "$(start_args w1)" "-m gpt-x" "codex model"
}

case_custom_slot() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"review-a":{"role":"scout","model":"prov/m2"}}}'
  hd_run spawn rv review-a
  assert_eq 0 "$HD_RC" "hd spawn rv review-a"
  assert_file_contains "$(start_args rv)" "--append-system-prompt $ROOT/roles/scout.md" "custom slot role"
  assert_file_contains "$(start_args rv)" "--model prov/m2" "custom slot model"
}

case_slot_flags() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"model":"prov/m2"}}}'
  hd_run spawn w1 worker --model prov/m1 --thinking low
  assert_eq 0 "$HD_RC" "hd spawn with model overrides"
  assert_file_contains "$(start_args w1)" "--model prov/m1" "flag model"
  assert_file_contains "$(start_args w1)" "--thinking low" "flag thinking"
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn without overrides"
  assert_file_contains "$(start_args w2)" "--model prov/m2" "slot model again"
  assert_file_not_contains "$(start_args w2)" "--thinking" "no thinking override"
}

case_codex_role_refused() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"sk":{"role":"sidekick","harness":"codex","model":"gpt-x"}}}'
  hd_run spawn x sk
  assert_eq 1 "$HD_RC" "codex sidekick"
  assert_contains "$HD_OUT" "scout, reviewer or worker" "codex role message"
  assert_eq 0 "$(pane_calls)" "panes after a codex role refusal"
}

case_fallback_codex_role_refused() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"sidekick":{"fallback":[{"harness":"codex"}]}}}'
  hd_run spawn x sidekick
  assert_eq 1 "$HD_RC" "fallback codex sidekick"
  assert_contains "$HD_OUT" "scout, reviewer or worker" "fallback codex role message"
  assert_eq 0 "$(pane_calls)" "panes after a fallback codex role refusal"
}

case_fallback_model_refused() {
  printf 'prov m1\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"fallback":[{"model":"prov/nope"}]}}}'
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "fallback model missing from pi"
  assert_contains "$HD_OUT" "prov/nope" "fallback model message"
  assert_eq 0 "$(pane_calls)" "panes after a fallback model refusal"
}

case_researcher_extensions() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"researcher":{"harness":"pi","model":"prov/m1"}}}'
  hd_run spawn rs researcher
  assert_eq 1 "$HD_RC" "researcher on pi without extensions"
  assert_contains "$HD_OUT" "pi_extensions" "researcher extension message"
  assert_eq 0 "$(pane_calls)" "panes after a researcher refusal"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"researcher":{"harness":"pi","model":"prov/m1","pi_extensions":["/x/web.ts"]}}}'
  hd_run spawn rs researcher
  assert_eq 0 "$HD_RC" "researcher on pi with extensions"
  assert_file_contains "$(start_args rs)" "-e /x/web.ts" "researcher extension"
}

case_provider_extension() {
  printf 'prov m1\ncc m9\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"model":"cc/m9"}},"providers":{"cc":{"pi_extension":"/x/cc.ts"}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn with a provider extension"
  assert_file_contains "$(start_args w1)" "-e /x/cc.ts" "provider extension"
  assert_file_contains "$FAKE_DIR/pi.calls" "-e /x/cc.ts" "provider extension on --list-models"
}

case_provider_extension_fallback() {
  printf 'prov m1\ncc m9\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"fallback":[{"model":"cc/m9"}]}},"providers":{"cc":{"pi_extension":"/x/cc.ts"}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn with a fallback provider extension"
  assert_eq 1 "$(grep -o -- "-e /x/cc.ts" "$(start_args w1)" | wc -l | tr -d ' ')" "provider extension once"
}

case_tilde_extension() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"pi_extensions":["~/x.ts"]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn with a tilde extension"
  assert_file_contains "$(start_args w1)" "-e $HOME/x.ts" "expanded extension"
}

case_codex_thinking_max() {
  hd_config '{"default":{"harness":"codex","model":"gpt-x","thinking":"max"}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn codex max"
  assert_file_contains "$(start_args w1)" 'model_reasoning_effort="xhigh"' "max maps to xhigh"
}

case_codex_thinking_default() {
  hd_config '{"default":{"harness":"codex","model":"gpt-x","thinking":"low"}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn codex from the default thinking"
  assert_file_contains "$(start_args w1)" 'model_reasoning_effort="low"' "default thinking"
  hd_config '{"default":{"harness":"codex","model":"gpt-x"}}'
  hd_run spawn w2 worker
  assert_eq 0 "$HD_RC" "hd spawn codex without thinking"
  assert_file_not_contains "$(start_args w2)" "model_reasoning_effort" "no effort without thinking"
}

case_spawn_records() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_eq "worker" "$(<"$(run_dir_entry w1.slot)")" "slot record"
  assert_eq "[]" "$(<"$(run_dir_entry w1.fallback)")" "fallback record"
}

case_env_empty_refused() {
  export HD_MODEL=
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with an empty HD_MODEL"
  assert_contains "$HD_OUT" "HD_MODEL" "variable in the message"
  assert_eq 0 "$(pane_calls)" "panes after an empty env refusal"
}

case_env_thinking_empty_refused() {
  export HD_THINKING=
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with an empty HD_THINKING"
  assert_contains "$HD_OUT" "HD_THINKING" "variable in the message"
  assert_eq 0 "$(pane_calls)" "panes after an empty HD_THINKING"
}

case_slot_default_role() {
  printf 'prov m1\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1","role":"worker"},"slots":{"custom":{}}}'
  hd_run spawn w custom
  assert_eq 0 "$HD_RC" "hd spawn w custom"
  assert_file_contains "$(start_args w)" "--append-system-prompt $ROOT/roles/worker.md" "default.role for a custom slot"
  hd_run spawn s scout
  assert_eq 0 "$HD_RC" "hd spawn s scout"
  assert_file_contains "$(start_args s)" "--append-system-prompt $ROOT/roles/scout.md" "built-in slot keeps its role"
}

case_resume_when_slot_gone() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"custom":{"role":"worker","model":"prov/m2"}}}'
  hd_run spawn w1 custom
  assert_eq 0 "$HD_RC" "hd spawn w1 custom"
  assert_file_contains "$(start_args w1)" "--model prov/m2" "custom model on spawn"
  hd_run stop w1
  assert_eq 0 "$HD_RC" "hd stop w1"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"}}'
  hd_run resume w1
  assert_eq 0 "$HD_RC" "hd resume after the slot is gone"
  assert_file_contains "$(start_args w1)" "--model prov/m2" "saved model on resume"
  assert_file_contains "$(start_args w1)" "--append-system-prompt $ROOT/roles/worker.md" "saved role on resume"
}
case_resume_keeps_slot() {
  printf 'prov m1\nprov m2\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"model":"prov/m2","pi_extensions":["/x/resume.ts"]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  assert_file_contains "$(start_args w1)" "-e /x/resume.ts" "slot extension on spawn"
  hd_run stop w1
  assert_eq 0 "$HD_RC" "hd stop w1"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "hd resume w1"
  assert_file_contains "$(start_args w1)" "--model prov/m2" "saved model on resume"
  assert_file_contains "$(start_args w1)" "-e /x/resume.ts" "slot extension on resume"
}

case_ls_model() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "hd spawn w1"
  hd_run ls
  assert_eq 0 "$HD_RC" "hd ls"
  local line
  line="$(grep '^w1 ' <<<"$HD_OUT")"
  [[ "$line" == *" model=prov/m1" ]] || t_fail "ls line does not end with the model: [$line]"
}

case_extensions_and_scout() {
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"pi_extensions":["/x/a.ts","/x/b.ts"]}}}'
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

case_reviewer_pi_tools() {
  hd_run spawn rv reviewer
  assert_eq 0 "$HD_RC" "hd spawn reviewer"
  assert_calls_nonempty
  local args tools
  args="$(start_args rv)"
  assert_file_contains "$args" "--append-system-prompt $ROOT/roles/reviewer.md" "reviewer role prompt"
  assert_file_contains "$args" "--tools read,grep,find,ls,bash,write,tool_search" "reviewer tools"
  tools="$(sed -n 's/.*--tools \([^ ]*\).*/\1/p' "$args")"
  assert_eq "read,grep,find,ls,bash,write,tool_search" "$tools" "reviewer tools"
  assert_not_contains "$tools" "edit" "reviewer tools"
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

case_codex_roles() {
  hd_run spawn sc scout --agent codex --model gpt-x --thinking low
  assert_eq 0 "$HD_RC" "hd spawn codex scout"
  local scout_args=("$FAKE_DIR"/agents/sc-*/start.args)
  assert_file_contains "${scout_args[0]}" "--kind codex"
  assert_file_contains "${scout_args[0]}" "-s workspace-write"
  assert_file_contains "${scout_args[0]}" "model_reasoning_effort=\"low\""

  hd_run spawn w1 worker --agent codex --model gpt-x
  assert_eq 0 "$HD_RC" "hd spawn codex worker"
  local worker_args=("$FAKE_DIR"/agents/w1-*/start.args)
  assert_file_contains "${worker_args[0]}" "-s danger-full-access"
  assert_file_not_contains "${worker_args[0]}" "workspace-write"
  assert_file_contains "${worker_args[0]}" "# Role: worker"

  hd_run spawn sk sidekick --agent codex
  assert_eq 1 "$HD_RC" "hd spawn codex sidekick"
  assert_contains "$HD_OUT" "scout, reviewer or worker only"
}

case_codex_reviewer() {
  hd_run spawn rv reviewer --agent codex --model gpt-x
  assert_eq 0 "$HD_RC" "hd spawn codex reviewer"
  local reviewer_args=("$FAKE_DIR"/agents/rv-*/start.args)
  assert_file_contains "${reviewer_args[0]}" "--kind codex"
  assert_file_contains "${reviewer_args[0]}" "-s workspace-write"

  hd_run spawn sk sidekick --agent codex --model gpt-x
  assert_eq 1 "$HD_RC" "hd spawn codex sidekick"
  assert_contains "$HD_OUT" "scout, reviewer or worker only"
}

case_model_near_miss_refused() {
  printf 'prov vendor/m1\nprov vendor/m1-ultrafast\nother m2\n' > "$FAKE_DIR/pi-models"
  hd_run spawn w1 worker --model prov/m1
  assert_eq 1 "$HD_RC" "hd spawn with a near-miss model"
  assert_contains "$HD_OUT" "no exact model prov/m1"
  assert_contains "$HD_OUT" "prov/vendor/m1"
  assert_contains "$HD_OUT" "prov/vendor/m1-ultrafast"
  assert_not_contains "$HD_OUT" "other/m2"
  [[ ! -e "$FAKE_DIR/agents" ]] || t_fail "an agent started for a near-miss model"
}

case_model_exact_accepted() {
  printf 'prov vendor/m1\nprov vendor/m1-ultrafast\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/m1"},"slots":{"worker":{"pi_extensions":["/x/provider.ts"]}}}'
  hd_run spawn w1 worker --model prov/vendor/m1
  assert_eq 0 "$HD_RC" "hd spawn with an exact model"
  assert_file_contains "$(single_agent_dir)/start.args" "--model prov/vendor/m1"
  assert_file_contains "$FAKE_DIR/pi.calls" "-e /x/provider.ts"

  hd_run spawn w2 worker --model vendor/m1:high
  assert_eq 0 "$HD_RC" "hd spawn with a bare ID and a thinking suffix"
}

case_default_model_near_miss_refused() {
  printf 'prov vendor/m1-fast\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"pi","model":"prov/vendor/m1"}}'
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "hd spawn with a near-miss default model"
  assert_contains "$HD_OUT" "prov/vendor/m1-fast"
}

run_case spawn_model_and_thinking case_model_thinking
run_case spawn_model_near_miss_refused case_model_near_miss_refused
run_case spawn_model_exact_accepted case_model_exact_accepted
run_case spawn_default_model_near_miss_refused case_default_model_near_miss_refused
run_case spawn_no_model case_no_model
run_case spawn_no_harness case_no_harness
run_case spawn_env_refused case_env_refused
run_case spawn_env_empty_refused case_env_empty_refused
run_case spawn_env_thinking_empty_refused case_env_thinking_empty_refused
run_case spawn_bad_json case_bad_json
run_case spawn_config_two_values case_config_two_values
run_case spawn_config_empty case_config_empty
run_case spawn_missing_config case_missing_config
run_case spawn_hd_config_path case_hd_config_path
run_case spawn_unknown_slot case_unknown_slot
run_case spawn_slot_model case_slot_model
run_case spawn_slot_harness case_slot_harness
run_case spawn_custom_slot case_custom_slot
run_case spawn_slot_default_role case_slot_default_role
run_case spawn_slot_flags case_slot_flags
run_case spawn_codex_role_refused case_codex_role_refused
run_case spawn_fallback_codex_role_refused case_fallback_codex_role_refused
run_case spawn_fallback_model_refused case_fallback_model_refused
run_case spawn_researcher_extensions case_researcher_extensions
run_case spawn_provider_extension case_provider_extension
run_case spawn_provider_extension_fallback case_provider_extension_fallback
run_case spawn_tilde_extension case_tilde_extension
run_case spawn_codex_thinking_max case_codex_thinking_max
run_case spawn_codex_thinking_default case_codex_thinking_default
run_case spawn_records case_spawn_records
run_case spawn_resume_keeps_slot case_resume_keeps_slot
run_case spawn_resume_when_slot_gone case_resume_when_slot_gone
run_case spawn_ls_model case_ls_model
run_case spawn_extensions_and_scout case_extensions_and_scout
run_case spawn_reviewer_pi_tools case_reviewer_pi_tools
run_case spawn_missing_cwd case_missing_cwd
run_case spawn_md5_fallback case_md5_fallback
run_case spawn_codex_roles case_codex_roles
run_case spawn_codex_reviewer case_codex_reviewer
