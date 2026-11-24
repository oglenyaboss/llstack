#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROVIDER_SECRET='TOP_SECRET_PROVIDER_KEY'

assert_jq_vars() {
  local input="$1" expr="$2" label="$3"; shift 3
  jq -e "$@" "$expr" >/dev/null 2>&1 <<< "$input" || t_fail "$label: jq [$expr] failed for [$input]"
}

zcode_setup() {
  export ZCODE_PERSONAL_PROVIDER_CONFIG_FILE="${ZCODE_PERSONAL_PROVIDER_CONFIG_FILE:-$CASE_TMP/provider.json}"
  mkdir -p "$(dirname "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE")"
  cat > "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE" <<JSON
{"schemaVersion":1,"config":{"providerOrder":["local"],"providerConfigRules":{"providerRules":[{"providerId":"local","providerName":"Local","config":{"access":{"type":"api-key","apiKey":"$PROVIDER_SECRET"},"api":{"type":"openai-chat-completions","baseUrl":"http://127.0.0.1:1/v1","headers":{"X-Trace":"keep"}},"personalModelIds":["base","vendor/model"]}}]},"modelConfigRules":{"providerModelRules":[],"manualProviderModelRules":[]},"defaultModelSelection":{"providerId":"local","modelId":"base","options":{"reasoningLevel":"low"}}}}
JSON
  local bin="$CASE_TMP/bin"
  mkdir -p "$bin"
  cat > "$bin/zcode" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
jq -nc --args '$ARGS.positional' -- "$@" >> "$FAKE_DIR/zcode.args"
{
  printf 'PWD=%s\n' "$PWD"
  printf 'HOME=%s\n' "${HOME:-}"
  printf 'USERPROFILE=%s\n' "${USERPROFILE:-}"
  printf 'ZCODE_DATA_BASE_DIR=%s\n' "${ZCODE_DATA_BASE_DIR:-}"
  printf 'ZCODE_SESSION_DB_PATH=%s\n' "${ZCODE_SESSION_DB_PATH:-}"
  printf 'ZCODE_STORAGE_DIR=%s\n' "${ZCODE_STORAGE_DIR:-}"
  printf 'ZCODE_LOG_DIR=%s\n' "${ZCODE_LOG_DIR:-}"
} >> "$FAKE_DIR/zcode.env"
SCRIPT
  chmod +x "$bin/zcode"
  export PATH="$bin:$PATH"
  hd_config '{"default":{"harness":"zcode","model":"local/base"}}'
}

zstate() { zcode_state_dir "${1:-w1}"; }

zc_pane() { cat "$(zstate "${1:-w1}")/pane"; }

zc_event() {
  local state="$1"; shift
  jq -nc "$@" >> "$state/events.jsonl"
}

zc_log() {
  local state="$1"; shift
  mkdir -p "$state/log"
  jq -nc "$@" >> "$state/log/zcode-test.jsonl"
}

zc_prompt_event() {
  local state="$1" session="$2" turn="$3" text="$4"
  zc_event "$state" --arg s "$session" --arg t "$turn" --arg p "$text" \
    '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p,cwd:"/tmp",mode:"yolo",timestamp:"2026-01-01T00:00:00Z"}'
}

zc_stop_event() {
  local state="$1" session="$2" turn="$3" text="$4"
  zc_event "$state" --arg s "$session" --arg t "$turn" --arg text "$text" \
    '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"preview",stopHookActive:false,toolCallCount:1,cwd:"/tmp",mode:"yolo",timestamp:"2026-01-01T00:00:01Z"}'
}

zc_completed_log() {
  local state="$1" session="$2" turn="$3"
  zc_log "$state" --arg s "$session" --arg t "$turn" \
    '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t,message:"Turn completed"}'
}

zc_failed_log() {
  local state="$1" session="$2" turn="$3" status="$4" message="$5"
  zc_log "$state" --arg s "$session" --arg t "$turn" --arg status "$status" --arg message "$message" \
    '{level:"error",event:"turn.failed",module:"core.runtime",status:$status,sessionId:$s,turnId:$t,message:"Turn failed",error:{name:"Error",message:$message}}'
}

zc_report() {
  local pane="$1" state="$2"
  herdr pane report-agent --source llstack:zcode --agent zcode --state "$state" "$pane" >/dev/null 2>&1 || true
}

write_on_enter() { cat > "$FAKE_DIR/on-enter"; chmod +x "$FAKE_DIR/on-enter"; }

send_count() { cat "$FAKE_DIR/panes/$1/send-count" 2>/dev/null || echo 0; }

request_json() { jq -Rn --arg p "$1" '$p'; }

assert_idle_after_first_send() {
  awk -F'\t' '
    $1 == "pane" && $2 == "send-text" { sends++ }
    $1 == "pane" && $2 == "report-agent" {
      for (i = 1; i <= NF; i++) if ($i == "--state" && $(i + 1) == "idle" && sends == 1) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$FAKE_DIR/calls.log" || t_fail "no idle report after the first failed turn"
}

case_invalid_name() {
  zcode_setup
  local victim="$XDG_CACHE_HOME/herdr-delegate/victim.zcode"
  mkdir -p "$victim"
  printf 'keep\n' > "$victim/sentinel"
  hd_run spawn ../victim worker
  assert_exists "$victim/sentinel" "invalid name cannot erase another profile"
  assert_eq 1 "$HD_RC" "invalid agent name"
  assert_contains "$HD_OUT" 'agent name' "invalid name diagnostic"
  [[ ! -s "$FAKE_DIR/calls.log" ]] || t_fail "invalid name reached Herdr"
}

case_spawn_tui() {
  zcode_setup
  printf 'Parent rule: inherit me.\n' > "$CASE_TMP/AGENTS.md"
  printf 'Project rule: keep it brief.\n' > AGENTS.md
  hd_config '{"default":{"harness":"zcode","model":"local/vendor/model","thinking":"high"}}'
  local source_before; source_before="$(cat "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE")"
  local caller_home="$HOME" caller_data="${ZCODE_DATA_BASE_DIR-}" caller_db="${ZCODE_SESSION_DB_PATH-}"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  assert_eq "$caller_home" "$HOME" "caller HOME untouched"
  assert_eq "$caller_data" "${ZCODE_DATA_BASE_DIR-}" "caller ZCODE_DATA_BASE_DIR untouched"
  assert_eq "$caller_db" "${ZCODE_SESSION_DB_PATH-}" "caller ZCODE_SESSION_DB_PATH untouched"
  [[ -x "$ROOT/zcode-launch" ]] || t_fail "zcode-launch is not executable"
  assert_contains "$HD_OUT" 'spawned w1 role=worker agent=zcode' "spawn line"
  assert_not_contains "$HD_OUT" "$PROVIDER_SECRET" "spawn output"

  local state pane run config
  state="$(zstate w1)"
  pane="$(zc_pane w1)"
  assert_mode 700 "$state" "zcode state dir"
  assert_mode 600 "$state/home/.zcode/v2/provider_config.json" "private provider"
  assert_eq "$source_before" "$(cat "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE")" "original provider unchanged"
  assert_jq '.config.defaultModelSelection == {providerId:"local",modelId:"vendor/model",options:{reasoningLevel:"high"}}' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "private model selection"
  assert_jq '.config.providerConfigRules.providerRules[0].config.api.headers["X-Trace"] == "keep"' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "private provider headers preserved"
  assert_jq '.config.providerOrder == ["local"]' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "private provider order preserved"

  config="$(cat "$state/home/.zcode/cli/config.json")"
  assert_jq '.features == {mcp:false,subagent:false,memory:false,skill:false}' "$config" "runtime features"
  assert_jq '.memory.use == false and .plugins.enabled == false and .skills.enabled == false' "$config" "runtime extensions"
  assert_jq '.hooks.enabled == true' "$config" "user hooks enabled"
  assert_jq '(.hooks.events | keys | sort) == ["PermissionRequest","PostToolUse","PostToolUseFailure","PreToolUse","SessionStart","Stop","UserPromptSubmit"]' "$config" "only named hook events"
  assert_jq_vars "$config" '[
    .hooks.events[][].hooks[]
    | select(.type == "process" and .command == "bash" and .args[0] == $hook and .args[1] == $state)
  ] | length == 7' "all hooks point at the private state" --arg hook "$ROOT/zcode-hook" --arg state "$state"
  [[ ! -e zcode.json ]] || t_fail "hd wrote zcode.json into the project"

  run="$(<"$FAKE_DIR/panes/$pane/run")"
  assert_contains "$run" "$ROOT/zcode-launch" "launcher"
  assert_contains "$run" "$state" "launcher state dir"
  assert_not_contains "$run" '--prompt' "launcher"
  assert_not_contains "$run" ' -p ' "launcher"
  assert_file_contains "$state/zcode-bin" '/zcode' "resolved zcode binary"
  assert_file_contains "$state/cwd" "$PWD" "launcher cwd"
  assert_file_contains "$state/disallowed" 'Agent' "disallowed tools"
  assert_contains "$(cat "$state/disallowed")" 'ExitPlanMode' "disallowed tools"

  local ctx parent_line role_line envelope_line project_line
  ctx="$(cat "$state/context.md")"
  assert_contains "$ctx" 'Parent rule: inherit me.' "context ancestor"
  assert_contains "$ctx" 'Project rule: keep it brief.' "context project"
  assert_contains "$ctx" '# Role: worker' "context role"
  assert_contains "$ctx" '## Envelope' "context envelope"
  parent_line="$(grep -n 'Parent rule' <<< "$ctx" | cut -d: -f1)"
  project_line="$(grep -n 'Project rule' <<< "$ctx" | cut -d: -f1)"
  role_line="$(grep -n '# Role: worker' <<< "$ctx" | cut -d: -f1)"
  envelope_line="$(grep -n '## Envelope' <<< "$ctx" | cut -d: -f1)"
  (( parent_line < project_line && project_line < role_line && role_line < envelope_line )) || t_fail "context order is ancestor, project, role, envelope"

  assert_contains "$(cat "$FAKE_DIR/calls.log")" $'pane\trun' "pane run"
  assert_contains "$(cat "$FAKE_DIR/calls.log")" $'pane\twait-output' "readiness wait-output"
  assert_contains "$(cat "$FAKE_DIR/calls.log")" $'pane\treport-agent' "idle report"
  assert_contains "$(cat "$FAKE_DIR/calls.log")" $'agent\trename' "agent rename"
  assert_not_contains "$(cat "$FAKE_DIR/calls.log")" $'agent\tstart' "zcode bypasses agent start"

  hd_run ls
  assert_eq 0 "$HD_RC" "zcode ls"
  assert_contains "$HD_OUT" 'w1 worker idle' "ls status"
  assert_contains "$HD_OUT" 'ctx=' "ls ctx is empty"
  assert_not_contains "$HD_OUT" 'ctx=0' "ls ctx is not invented"
}

case_spawn_failure() {
  zcode_setup
  cat > "$FAKE_DIR/on-pane-run" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: > "$FAKE_DIR/panes/$1/fail-ready"
SCRIPT
  chmod +x "$FAKE_DIR/on-pane-run"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn without readiness"
  assert_contains "$HD_OUT" 'did not become ready' "startup failure"
  assert_contains "$HD_OUT" 'SCREEN TAIL' "startup failure screen"
  assert_not_contains "$HD_OUT" 'spawned w1' "no false readiness"
}

case_preflight() {
  zcode_setup
  local calls=0
  pane_calls() {
    [[ -f "$FAKE_DIR/calls.log" ]] || { echo 0; return; }
    grep -c -E $'^(pane\t(split|run)|tab\tcreate)' "$FAKE_DIR/calls.log" || true
  }

  export PATH="$(path_without zcode)"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn without zcode"
  assert_contains "$HD_OUT" 'zcode is not on PATH' "missing binary message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after missing binary"

  zcode_setup
  rm -f "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn without provider config"
  assert_contains "$HD_OUT" 'personal provider config' "missing provider message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after missing provider"

  zcode_setup
  hd_run spawn w1 worker --model 'noslash'
  assert_eq 1 "$HD_RC" "spawn with a bad model"
  assert_contains "$HD_OUT" 'providerId/modelId' "bad model message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after bad model"

  zcode_setup
  hd_config '{"default":{"harness":"zcode","model":"local/base"},"slots":{"ghost":{"role":"no-such-role"}}}'
  hd_run spawn w1 ghost
  assert_eq 1 "$HD_RC" "spawn with an unknown role"
  assert_contains "$HD_OUT" 'no role file' "bad role message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after bad role"

  zcode_setup
  hd_run spawn w1 ../SKILL
  assert_eq 1 "$HD_RC" "a role cannot be a path outside roles"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after a role path"

  zcode_setup
  printf '{"schemaVersion":1,"apiKey":"%s"\n' "$PROVIDER_SECRET" > "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn with a malformed provider"
  assert_not_contains "$HD_OUT" "$PROVIDER_SECRET" "malformed provider leak"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after malformed provider"

  zcode_setup
  jq '.config.providerConfigRules.providerRules = []' "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE" > "$CASE_TMP/provider-no-rules.json"
  mv "$CASE_TMP/provider-no-rules.json" "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn without a provider rule"
  assert_contains "$HD_OUT" 'API-key' "missing provider message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after missing provider rule"

  zcode_setup
  jq '.config.providerConfigRules.providerRules[0].providerId = "elsewhere"' "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE" > "$CASE_TMP/provider-other.json"
  mv "$CASE_TMP/provider-other.json" "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn with an unselected provider"
  assert_contains "$HD_OUT" 'API-key' "unselected provider message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after unselected provider"

  zcode_setup
  jq '.config.providerConfigRules.providerRules[0].config.access = {"type":"oauth"}' "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE" > "$CASE_TMP/provider-oauth.json"
  mv "$CASE_TMP/provider-oauth.json" "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn without API-key access"
  assert_contains "$HD_OUT" 'API-key' "non API-key access message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after non API-key access"

  zcode_setup
  jq '.config.providerConfigRules.providerRules[0].config.access.apiKey = "   "' "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE" > "$CASE_TMP/provider-empty-key.json"
  mv "$CASE_TMP/provider-empty-key.json" "$ZCODE_PERSONAL_PROVIDER_CONFIG_FILE"
  hd_run spawn w1 worker
  assert_eq 1 "$HD_RC" "spawn with an empty API key"
  assert_contains "$HD_OUT" 'API-key' "empty API-key message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after empty API key"

  zcode_setup
  hd_run spawn w1 worker --session "$CASE_TMP/rollout.jsonl"
  assert_eq 1 "$HD_RC" "spawn with a foreign session"
  assert_contains "$HD_OUT" 'hd resume' "foreign session message"
  calls="$(pane_calls)"
  assert_eq 0 "$calls" "panes after foreign session"
}

case_ask_request() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
mkdir -p src
printf 'b\n' > src/b.txt
request="$(<"$state/request")"
payload="$(sed -n 's/^OUTPUT_FILE: //p' "$request" | tail -n 1)"
printf 'payload\n' > "$payload"
jq -nc --arg s sess-ask --arg t turn-ask --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p,cwd:"/tmp",mode:"yolo",timestamp:"2026-01-01T00:00:00Z"}' >> "$state/events.jsonl"
jq -nc --arg s sess-ask --arg t turn-ask --arg text $'did it\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"did it",stopHookActive:false,toolCallCount:1,cwd:"/tmp",mode:"yolo",timestamp:"2026-01-01T00:00:01Z"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-ask --arg t turn-ask \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  local brief='Do the work.

Check: `test -f src/b.txt`
Scope: `src/b.txt`'
  hd_run ask w1 "$brief"
  assert_eq 0 "$HD_RC" "zcode ask"
  assert_contains "$HD_OUT" 'did it' "reply"
  assert_contains "$HD_OUT" 'ctx=' "empty ctx"
  assert_not_contains "$HD_OUT" 'ctx=0' "ctx is not invented"
  assert_contains "$HD_OUT" '--- check: test -f src/b.txt' "check"
  assert_contains "$HD_OUT" 'exit=0' "check exit"
  assert_contains "$HD_OUT" '--- scope: 1 changed, 0 outside Scope' "scope"

  local request line quoted payload
  request="$(<"$state/request")"
  assert_exists "$request" "request file"
  assert_mode 600 "$request" "request file"
  assert_file_contains "$request" 'Do the work.' "request brief"
  assert_file_contains "$request" 'Check: `test -f src/b.txt`' "request check"
  assert_file_contains "$request" 'OUTPUT_FILE: ' "request output file"
  assert_file_contains "$request" 'Write the payload' "request envelope"
  assert_mode 700 "$state" "private state dir"

  line="$(<"$FAKE_DIR/panes/$(zc_pane w1)/send-text")"
  quoted="$(request_json "$request")"
  case "$line" in
    *$'\n'*) t_fail "submitted request is multiline" ;;
  esac
  assert_contains "$line" "$quoted" "submitted JSON path"
  assert_contains "$line" 'execute' "submitted instruction"
  assert_not_contains "$line" 'Do the work.' "brief text is not pasted"
  assert_file_contains "$FAKE_DIR/panes/$(zc_pane w1)/send-keys" 'enter' "send-keys"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "one submission"
  assert_not_contains "$(cat "$FAKE_DIR/calls.log")" $'agent\tprompt' "no agent prompt for zcode"

  local entry
  entry="$(jq -c 'select(.event == "ask")' "$XDG_CACHE_HOME/herdr-delegate/journal.jsonl")"
  assert_jq '.agent == "zcode" and .status == "STATUS: done" and .check_exit == "0"' "$entry" "journal"
  payload="$(sed -n 's/^OUTPUT_FILE: //p' <<< "$(<"$request")" | tail -n 1)"
  assert_jq_vars "$entry" '.payload == $payload' "journal payload" --arg payload "$payload"
  assert_file_contains "$state/session-id" 'sess-ask' "session id saved"

  hd_run result w1
  assert_eq 0 "$HD_RC" "zcode result"
  assert_contains "$HD_OUT" 'did it' "result reply"
  assert_contains "$HD_OUT" 'STATUS: done' "result status"

  hd_run diff w1
  assert_eq 0 "$HD_RC" "zcode diff"
  assert_contains "$HD_OUT" 'src/b.txt' "diff after a zcode ask"
}

case_followup() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
count="$(cat "$FAKE_DIR/on-enter-count" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_DIR/on-enter-count"
if (( count == 1 )); then
  session=sess-first; turn=turn-first; text=$'FIRST REPLY\nSTATUS: done'
else
  session=sess-second; turn=turn-second; text=$'SECOND REPLY\nSTATUS: done'
fi
jq -nc --arg s "$session" --arg t "$turn" --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s "$session" --arg t "$turn" --arg text "$text" \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"preview"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s "$session" --arg t "$turn" \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'First task.'
  assert_eq 0 "$HD_RC" "first ask"
  assert_contains "$HD_OUT" 'FIRST REPLY' "first reply"
  local first_request; first_request="$(<"$state/request")"
  hd_run ask w1 'Second task.'
  assert_eq 0 "$HD_RC" "second ask"
  assert_contains "$HD_OUT" 'SECOND REPLY' "second reply"
  assert_not_contains "$HD_OUT" 'FIRST REPLY' "second ask uses only the fresh reply"
  assert_eq 2 "$(( $(wc -l < "$XDG_CACHE_HOME/herdr-delegate/journal.jsonl") ))" "journal lines"
  local second_request; second_request="$(<"$state/request")"
  [[ "$first_request" != "$second_request" ]] || t_fail "each ask has its own request file"
  hd_run result w1
  assert_contains "$HD_OUT" 'SECOND REPLY' "result after second ask"
  assert_not_contains "$HD_OUT" 'FIRST REPLY' "result after second ask is fresh"
}

case_wait_timeout_then_wait() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-wait --arg t turn-wait --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Wait on me.' --timeout 300
  assert_eq 0 "$HD_RC" "ask timeout exit"
  assert_contains "$HD_OUT" 'STATUS: still_working' "ask timeout"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "no resend after timeout"
  zc_stop_event "$state" sess-wait turn-wait $'late reply\nSTATUS: done'
  zc_completed_log "$state" sess-wait turn-wait
  hd_run wait w1 --timeout 3000
  assert_eq 0 "$HD_RC" "later wait"
  assert_contains "$HD_OUT" 'late reply' "later wait reply"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "later wait does not resend"
}

case_wait_blocked() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state pane; state="$(zstate w1)"; pane="$(zc_pane w1)"
  printf 'PERMISSION DIALOG\n' > "$FAKE_DIR/panes/$pane/screen"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-block --arg t turn-block --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state blocked "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Blocked task.' --timeout 300
  assert_eq 0 "$HD_RC" "blocked ask exit"
  assert_contains "$HD_OUT" 'STATUS: blocked_ui' "blocked status"
  assert_contains "$HD_OUT" 'PERMISSION DIALOG' "blocked visible output"
  assert_eq 1 "$(send_count "$pane")" "blocked does not resend"
}

case_wait_stale_turns() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  zc_prompt_event "$state" sess-old turn-old 'OLD REQUEST'
  zc_stop_event "$state" sess-old turn-old $'OLD REPLY\nSTATUS: done'
  zc_completed_log "$state" sess-old turn-old
  zc_failed_log "$state" sess-old turn-old failed "$PROVIDER_SECRET"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-now --arg t turn-now --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-now --arg t turn-manual \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:"MANUAL REQUEST"}' >> "$state/events.jsonl"
jq -nc --arg s sess-now --arg t turn-manual --arg text $'MANUAL REPLY\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"manual"}' >> "$state/events.jsonl"
jq -nc --arg s sess-other --arg t turn-now --arg text $'OTHER SESSION\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"other"}' >> "$state/events.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Current task.' --timeout 300
  assert_eq 0 "$HD_RC" "stale ask exit"
  assert_contains "$HD_OUT" 'STATUS: still_working' "stale and unrelated events do not settle"
  assert_not_contains "$HD_OUT" 'OLD REPLY' "old reply ignored"
  assert_not_contains "$HD_OUT" 'MANUAL REPLY' "manual turn ignored"
  assert_not_contains "$HD_OUT" 'OTHER SESSION' "other session ignored"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "stale wait does not resend"
  zc_stop_event "$state" sess-now turn-now $'CURRENT REPLY\nSTATUS: done'
  zc_completed_log "$state" sess-now turn-now
  hd_run wait w1 --timeout 3000
  assert_contains "$HD_OUT" 'CURRENT REPLY' "current turn settles"
  assert_not_contains "$HD_OUT" 'OLD REPLY' "stale stop never reused"
}

case_wait_no_reply() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-none --arg t turn-none --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-none --arg t turn-none \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responsePreview:"PREVIEW_TEXT",stopHookActive:false}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-none --arg t turn-none \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'No response text.' --timeout 3000
  assert_eq 0 "$HD_RC" "no_reply ask exit"
  assert_contains "$HD_OUT" 'STATUS: no_reply' "no_reply status"
  assert_not_contains "$HD_OUT" 'PREVIEW_TEXT' "preview is not the full response"
}

case_provider_retry() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
count="$(cat "$FAKE_DIR/on-enter-count" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_DIR/on-enter-count"
mkdir -p "$state/log"
if (( count == 1 )); then
  jq -nc --arg s sess-p1 --arg t turn-p1 --arg p "$(<"$state/line")" \
    '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
  jq -nc --arg s sess-p1 --arg t turn-p1 --arg m 'TOP_SECRET_API_RESPONSE' \
    '{level:"error",event:"turn.failed",module:"core.runtime",status:"failed",sessionId:$s,turnId:$t,message:"Turn failed",error:{name:"Error",message:$m}}' >> "$state/log/zcode-test.jsonl"
  herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
else
  jq -nc --arg s sess-p2 --arg t turn-p2 --arg p "$(<"$state/line")" \
    '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
  jq -nc --arg s sess-p2 --arg t turn-p2 --arg text $'recovered\nSTATUS: done' \
    '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"recovered"}' >> "$state/events.jsonl"
  jq -nc --arg s sess-p2 --arg t turn-p2 \
    '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
  herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
fi
SCRIPT
  hd_run ask w1 'Retry me.' --timeout 3000
  assert_eq 0 "$HD_RC" "retry ask exit"
  assert_contains "$HD_OUT" 'recovered' "retry reply"
  assert_eq 2 "$(send_count "$(zc_pane w1)")" "retry once"
  assert_not_contains "$HD_OUT" 'TOP_SECRET_API_RESPONSE' "retry hides the raw error"
  assert_idle_after_first_send
  local retry_request
  retry_request="$(ls "$state"/requests/* | tail -n 1)"
  assert_contains "$retry_request" 'retry' "retry request file"
  assert_file_contains "$retry_request" 'diagnostics:' "retry request diagnostics"
  assert_file_not_contains "$retry_request" 'TOP_SECRET_API_RESPONSE' "retry request hides the raw error"
  assert_mode 600 "$retry_request" "retry request mode"
  case "$(cat "$FAKE_DIR/panes/$(zc_pane w1)/send-text-2")" in
    *$'\n'*) t_fail "retry is multiline" ;;
  esac
}

case_provider_failure_twice() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
count="$(cat "$FAKE_DIR/on-enter-count" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_DIR/on-enter-count"
mkdir -p "$state/log"
jq -nc --arg s "sess-f$count" --arg t "turn-f$count" --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s "sess-f$count" --arg t "turn-f$count" --arg m 'TOP_SECRET_API_RESPONSE' \
  '{level:"error",event:"turn.failed",module:"core.runtime",status:"failed",sessionId:$s,turnId:$t,message:"Turn failed",error:{name:"Error",message:$m}}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Fail twice.' --timeout 3000
  assert_eq 0 "$HD_RC" "provider failure exit"
  assert_contains "$HD_OUT" 'STATUS: provider_error' "provider_error"
  assert_contains "$HD_OUT" "diagnostics: $state/log" "diagnostics path"
  assert_not_contains "$HD_OUT" 'TOP_SECRET_API_RESPONSE' "provider failure hides the raw error"
  assert_eq 2 "$(send_count "$(zc_pane w1)")" "only one retry"
  assert_idle_after_first_send
}

case_fallback_to_pi() {
  zcode_setup
  printf 'prov m1\n' > "$FAKE_DIR/pi-models"
  hd_config '{"default":{"harness":"zcode","model":"local/base"},"slots":{"worker":{"fallback":[{"harness":"pi","model":"prov/m1"}]}}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
count="$(cat "$FAKE_DIR/on-enter-count" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_DIR/on-enter-count"
mkdir -p "$state/log"
jq -nc --arg s "sess-f$count" --arg t "turn-f$count" --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s "sess-f$count" --arg t "turn-f$count" --arg m 'TOP_SECRET_API_RESPONSE' \
  '{level:"error",event:"turn.failed",module:"core.runtime",status:"failed",sessionId:$s,turnId:$t,message:"Turn failed",error:{name:"Error",message:$m}}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  write_hook <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HD_TEST_LIB"
turn "$2" "moved off zcode
STATUS: done"
EOF
  hd_run ask w1 'Fail twice, then switch.' --timeout 3000
  assert_eq 0 "$HD_RC" "fallback ask exit"
  assert_contains "$HD_OUT" '--- fallback: local/base → prov/m1' "fallback line"
  assert_contains "$HD_OUT" 'STATUS: done' "replacement envelope"
  assert_contains "$HD_OUT" 'moved off zcode' "replacement reply"
  local agent_file
  agent_file="$(find "$XDG_CACHE_HOME/herdr-delegate" -name w1.agent -print -quit)"
  assert_eq 'pi' "$(cat "$agent_file")" ".agent after the switch"
}

case_cancelled() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-cancel --arg t turn-cancel --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-cancel --arg t turn-cancel \
  '{level:"error",event:"turn.failed",module:"core.runtime",status:"cancelled",sessionId:$s,turnId:$t,message:"Turn failed"}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Cancel me.' --timeout 3000
  assert_eq 0 "$HD_RC" "cancelled ask exit"
  assert_contains "$HD_OUT" 'STATUS: cancelled' "cancelled status"
  assert_not_contains "$HD_OUT" 'STATUS: provider_error' "cancelled does not retry"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "cancelled does not resend"
  assert_idle_after_first_send
}

case_stop_resume() {
  zcode_setup
  hd_config '{"default":{"harness":"zcode","model":"local/vendor/model","thinking":"high"}}'
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  printf 'resume db sentinel\n' > "$state/db/db.sqlite"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-resume --arg t turn-resume --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-resume --arg t turn-resume --arg text $'before stop\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"before stop"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-resume --arg t turn-resume \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Before stop.'
  assert_eq 0 "$HD_RC" "ask before stop"
  assert_file_contains "$state/session-id" 'sess-resume' "saved hook session"
  local provider_before; provider_before="$(cat "$state/home/.zcode/v2/provider_config.json")"
  hd_run stop w1
  assert_eq 0 "$HD_RC" "zcode stop"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "zcode resume"
  assert_contains "$HD_OUT" 'spawned w1 role=worker agent=zcode' "resume spawn line"
  assert_eq "$state" "$(zstate w1)" "resume keeps the private state dir"
  assert_eq "$provider_before" "$(cat "$state/home/.zcode/v2/provider_config.json")" "resume keeps provider snapshot"
  assert_file_contains "$state/db/db.sqlite" 'resume db sentinel' "resume keeps the session DB"
  assert_eq 'high' "$(jq -r '.config.defaultModelSelection.options.reasoningLevel' "$state/home/.zcode/v2/provider_config.json")" "resume keeps thinking"

  hd_run stop w1
  assert_eq 0 "$HD_RC" "second stop"
  local runs; runs="$(grep -c $'^pane\trun\t' "$FAKE_DIR/calls.log" 2>/dev/null || true)"
  hd_run resume w1 --thinking low
  assert_eq 1 "$HD_RC" "resume rejects a different thinking"
  assert_contains "$HD_OUT" 'persisted' "resume override message"
  assert_eq "$runs" "$(grep -c $'^pane\trun\t' "$FAKE_DIR/calls.log" 2>/dev/null || true)" "rejected thinking creates no pane"
  hd_run resume w1 --model other/model
  assert_eq 1 "$HD_RC" "resume rejects a different model"
  assert_contains "$HD_OUT" 'persisted' "resume model override message"
  assert_eq "$runs" "$(grep -c $'^pane\trun\t' "$FAKE_DIR/calls.log" 2>/dev/null || true)" "rejected model creates no pane"
  hd_run resume w1 --model local/vendor/model --thinking high
  assert_eq 0 "$HD_RC" "resume with the saved model and thinking"

  local pane run args envfile cwd_value
  pane="$(zc_pane w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_PANE_ID="$pane"; cd "$PWD"; bash -c "$run" )
  args="$(tail -n 1 "$FAKE_DIR/zcode.args")"
  assert_jq 'index("--resume") as $i | .[$i + 1] == "sess-resume"' "$args" "resume session id"
  assert_jq 'index("--locale") as $i | .[$i + 1] == "en-US"' "$args" "locale"
  assert_jq 'index("--mode") as $i | .[$i + 1] == "yolo"' "$args" "mode"
  assert_jq 'index("--workflow-mode") as $i | .[$i + 1] == "disabled"' "$args" "workflow mode"
  cwd_value="$(jq -r 'index("--cwd") as $i | .[$i + 1]' <<< "$args")"
  assert_eq "$PWD" "$cwd_value" "cwd"
  envfile="$(cat "$FAKE_DIR/zcode.env")"
  state="$(cd "$state" && pwd -P)"
  assert_contains "$envfile" "HOME=$state/home" "private HOME"
  assert_contains "$envfile" "ZCODE_SESSION_DB_PATH=$state/db/db.sqlite" "private session DB"
  assert_contains "$envfile" "ZCODE_LOG_DIR=$state/log" "private log dir"
  assert_contains "$envfile" "ZCODE_STORAGE_DIR=$state/storage" "private storage dir"
  assert_contains "$(cat "$FAKE_DIR/calls.log")" $'pane\trelease-agent' "launcher releases on exit"
}

case_resume_after_tui_exit() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state pane run newpane
  state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-exit --arg t turn-exit --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-exit --arg t turn-exit --arg text $'done before exit\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"done"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-exit --arg t turn-exit \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Finish before exit.'
  assert_eq 0 "$HD_RC" "ask before exit"
  pane="$(zc_pane w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_ENV=1 HERDR_PANE_ID="$pane"; bash -c "$run" )
  assert_exists "$state/launcher-exit.$(<"$state/launcher-pid")" "launcher exit after completion"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "resume after a normal TUI exit"
  assert_contains "$HD_OUT" 'spawned w1' "resume spawn line"
  newpane="$(zc_pane w1)"
  [[ "$newpane" != "$pane" ]] || t_fail "resume reused the exited pane"
}

case_resume_manual_session() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "spawn before manual use"
  local state pane run args
  state="$(zstate w1)"; pane="$(zc_pane w1)"
  zc_event "$state" '{hookEventName:"SessionStart",sessionId:"sess-manual",source:"startup"}'
  zc_stop_event "$state" sess-manual turn-manual 'Manual answer'
  [[ ! -e "$state/session-id" ]] || t_fail "a manual session was already cached by hd"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_ENV=1 HERDR_PANE_ID="$pane"; bash -c "$run" )
  hd_run resume w1
  assert_eq 0 "$HD_RC" "resume after manual use and exit"
  pane="$(zc_pane w1)"; run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_ENV=0 HERDR_PANE_ID="$pane"; bash -c "$run" )
  args="$(tail -n 1 "$FAKE_DIR/zcode.args")"
  assert_jq 'index("--resume") as $i | $i != null and .[$i + 1] == "sess-manual"' "$args" "manual conversation is resumed"
}

case_resume_empty() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  hd_run stop w1
  assert_eq 0 "$HD_RC" "stop before an ask"
  [[ ! -e "$state/session-id" ]] || t_fail "an empty session left a session id"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "resume an empty session"
  local pane run
  pane="$(zc_pane w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_PANE_ID="$pane"; cd "$PWD"; bash -c "$run" )
  assert_jq 'index("--resume") == null' "$(tail -n 1 "$FAKE_DIR/zcode.args")" "fresh TUI without --resume"
}

case_paths_quotes() {
  local cache="$CASE_TMP/cache dir's" work="$CASE_TMP/work dir's" provider="$CASE_TMP/provider's.json"
  export XDG_CACHE_HOME="$cache"
  export ZCODE_PERSONAL_PROVIDER_CONFIG_FILE="$provider"
  mkdir -p "$cache" "$work/src"
  git -C "$work" init -q
  printf 'base\n' > "$work/src/a.txt"
  git -C "$work" add src/a.txt
  git -C "$work" -c user.name=test -c user.email=test@example.com commit -qm init
  zcode_setup
  cd "$work"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "spawn in quoted paths"
  local state pane request line run mark offset
  state="$(zcode_state_dir w1)"
  pane="$(cat "$state/pane")"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
request="$(<"$state/request")"
payload="$(sed -n 's/^OUTPUT_FILE: //p' "$request" | tail -n 1)"
printf 'payload\n' > "$payload"
count="$(cat "$FAKE_DIR/on-enter-count" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_DIR/on-enter-count"
jq -nc --arg s "sess-quote$count" --arg t "turn-quote$count" --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s "sess-quote$count" --arg t "turn-quote$count" --arg text "quoted reply $count\nSTATUS: done" \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"quoted"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s "sess-quote$count" --arg t "turn-quote$count" \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Quoted path task.'
  assert_eq 0 "$HD_RC" "ask in quoted paths"
  assert_contains "$HD_OUT" 'quoted reply 1' "quoted reply"
  request="$(<"$state/request")"
  line="$(<"$FAKE_DIR/panes/$pane/send-text")"
  assert_contains "$line" "$(request_json "$request")" "quoted request path is JSON"
  hd_run ask w1 'Second quoted task.'
  assert_eq 0 "$HD_RC" "second ask in quoted paths"
  assert_contains "$HD_OUT" 'quoted reply 2' "second quoted reply"
  assert_not_contains "$HD_OUT" 'quoted reply 1' "second quoted ask is fresh"
  mark="$(dirname "$state")/w1.mark"
  assert_eq "$state/events.jsonl" "$(sed -n '1p' "$mark")" "mark records the quoted events path"
  assert_eq 2 "$(sed -n '2p' "$mark")" "mark records the line offset"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_PANE_ID="$pane"; cd "$work"; bash -c "$run" )
  assert_eq 0 "$?" "quoted launcher command"
}

case_spawn_fresh() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "first spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-old --arg t turn-old --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-old --arg t turn-old --arg text $'old reply\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"old"}' >> "$state/events.jsonl"
mkdir -p "$state/log"
jq -nc --arg s sess-old --arg t turn-old \
  '{level:"info",event:"turn.completed",module:"core.runtime",status:"completed",sessionId:$s,turnId:$t}' >> "$state/log/zcode-test.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state idle "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Old task.'
  assert_eq 0 "$HD_RC" "ask before respawn"
  assert_file_contains "$state/events.jsonl" 'sess-old' "old events exist"
  hd_run stop w1
  assert_eq 0 "$HD_RC" "stop before respawn"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "fresh respawn"
  [[ ! -e "$state/events.jsonl" ]] || t_fail "a fresh spawn kept old events"
  [[ ! -e "$state/session-id" ]] || t_fail "a fresh spawn kept the old session"
  local pane run
  pane="$(zc_pane w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( export HERDR_PANE_ID="$pane"; cd "$PWD"; bash -c "$run" )
  assert_jq 'index("--resume") == null' "$(tail -n 1 "$FAKE_DIR/zcode.args")" "fresh respawn has no --resume"
}

case_wait_stop_before_log() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-stop --arg t turn-stop --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
jq -nc --arg s sess-stop --arg t turn-stop --arg text $'PROVISIONAL STOP\nSTATUS: done' \
  '{hookEventName:"Stop",sessionId:$s,turnId:$t,responseText:$text,responsePreview:"provisional"}' >> "$state/events.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  hd_run ask w1 'Provisional stop.' --timeout 300
  assert_eq 0 "$HD_RC" "provisional ask exit"
  assert_contains "$HD_OUT" 'STATUS: still_working' "a Stop without a terminal log does not settle"
  hd_run result w1
  assert_eq 0 "$HD_RC" "result before settlement"
  assert_contains "$HD_OUT" 'STATUS: no_reply' "an unsettled Stop has no result"
  assert_not_contains "$HD_OUT" 'PROVISIONAL STOP' "result does not print a provisional Stop"
  zc_completed_log "$state" sess-stop turn-stop
  hd_run wait w1 --timeout 3000
  assert_eq 0 "$HD_RC" "wait after terminal log"
  assert_contains "$HD_OUT" 'PROVISIONAL STOP' "the terminal log releases the full Stop text"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "settlement does not resend"
}

case_wait_deadline() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  cat > "$FAKE_DIR/on-agent-get" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
sleep 0.6
SCRIPT
  chmod +x "$FAKE_DIR/on-agent-get"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-deadline --arg t turn-deadline --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$pane" >/dev/null 2>&1 || true
SCRIPT
  local runner=() start end elapsed
  [[ -n "$TIMEOUT" ]] && runner=("$TIMEOUT" 8)
  start="$(date +%s)"
  set +e
  HD_OUT="$("${runner[@]}" "$HD" ask w1 'Deadline task.' --timeout 1000 2>&1)"
  HD_RC=$?
  set -e
  end="$(date +%s)"
  elapsed=$((end - start))
  assert_eq 0 "$HD_RC" "deadline ask exit"
  assert_contains "$HD_OUT" 'STATUS: still_working' "deadline ask status"
  (( elapsed <= 4 )) || t_fail "timeout used subprocess iterations: ${elapsed}s for a 1s deadline"
}

case_stale_launcher_exit() {
  zcode_setup
  cat > "$CASE_TMP/bin/zcode" <<'SCRIPT'
#!/usr/bin/env bash
: > "$FAKE_DIR/$ZCODE_TEST_LAUNCH.started"
while [[ ! -f "$FAKE_DIR/$ZCODE_TEST_LAUNCH.release" ]]; do sleep 0.01; done
SCRIPT
  local old_pid="" new_pid="" pane run state first_out first_rc
  cleanup_launchers() {
    touch "$FAKE_DIR/old.release" "$FAKE_DIR/new.release"
    [[ -z "$old_pid" ]] || wait "$old_pid" || true
    [[ -z "$new_pid" ]] || wait "$new_pid" || true
  }
  wait_started() {
    local i
    for ((i = 0; i < 200; i++)); do
      [[ -f "$FAKE_DIR/$1.started" ]] && return 0
      sleep 0.01
    done
    t_fail "launcher $1 did not start"
  }
  trap cleanup_launchers EXIT
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "first spawn"
  pane="$(zc_pane w1)"; state="$(zstate w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  HERDR_ENV=0 ZCODE_TEST_LAUNCH=old bash -c "$run" & old_pid=$!
  wait_started old
  hd_run stop w1
  assert_eq 0 "$HD_RC" "stop while the old launcher is draining"
  hd_run resume w1
  assert_eq 0 "$HD_RC" "resume before the old launcher exits"
  pane="$(zc_pane w1)"; run="$(<"$FAKE_DIR/panes/$pane/run")"
  HERDR_ENV=0 ZCODE_TEST_LAUNCH=new bash -c "$run" & new_pid=$!
  wait_started new
  touch "$FAKE_DIR/old.release"
  wait "$old_pid"
  hd_run ask w1 'Wait for the new TUI.' --timeout 100
  first_out="$HD_OUT"; first_rc="$HD_RC"
  cleanup_launchers
  trap - EXIT
  assert_eq 0 "$first_rc" "ask after a late old exit"
  assert_contains "$first_out" 'STATUS: still_working' "a late old exit cannot stop the new request"
  assert_not_contains "$first_out" 'STATUS: tui_exited' "the new TUI is still running"
  hd_run wait w1 --timeout 100
  assert_contains "$HD_OUT" 'STATUS: tui_exited' "the current launcher exit is detected"
}

case_launcher_exit() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state pane run; state="$(zstate w1)"; pane="$(zc_pane w1)"
  run="$(<"$FAKE_DIR/panes/$pane/run")"
  ( unset HERDR_ENV; export HERDR_PANE_ID="$pane"; bash -c "$run" )
  local marker="$state/launcher-exit.$(<"$state/launcher-pid")"
  assert_exists "$marker" "launcher exit marker"
  [[ "$(cat "$marker")" == *'status=0'* ]] || t_fail "launcher exit marker lost the status"
  hd_run ask w1 'Exit before the hook.' --timeout 3000
  assert_eq 0 "$HD_RC" "launcher exit ask exit"
  assert_contains "$HD_OUT" 'STATUS: tui_exited' "launcher exit is a concrete failure"
  assert_contains "$HD_OUT" 'launcher-exit' "launcher exit diagnostics"
  assert_not_contains "$HD_OUT" 'STATUS: still_working' "launcher exit does not wait forever"
}

case_pi_context_newline() {
  local project="$CASE_TMP/project"$'\n'"nested"
  mkdir -p "$project"
  printf 'Newline project rule.\n' > "$project/AGENTS.md"
  hd_run spawn w1 worker --cwd "$project"
  assert_eq 0 "$HD_RC" "pi spawn in a newline path"
  local args; args="$(single_agent_dir)/start.args"
  assert_file_contains "$args" "--append-system-prompt $project/AGENTS.md" "newline context path stays one argument"
}

case_pi_old_mark() {
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "pi spawn"
  local dir session rd role_file
  dir="$(single_agent_dir)"
  session="$dir/session.jsonl"
  turn "$session" 'OLD STALE REPLY'
  role_file="$(find "$XDG_CACHE_HOME/herdr-delegate" -name w1.role -print -quit)"
  [[ -n "$role_file" ]] || t_fail "no pi run state"
  rd="$(dirname "$role_file")"
  printf '%s %s\n' "$session" 1 > "$rd/w1.mark"
  hd_run result w1
  assert_eq 0 "$HD_RC" "result with an old mark"
  assert_contains "$HD_OUT" 'STATUS: no_reply' "the old mark excludes the old reply"
  assert_not_contains "$HD_OUT" 'OLD STALE REPLY' "the old reply is not reused"
  turn "$session" 'ONLY FRESH REPLY'
  hd_run result w1
  assert_eq 0 "$HD_RC" "result after fresh output"
  assert_contains "$HD_OUT" 'ONLY FRESH REPLY' "the fresh reply is returned"
  assert_not_contains "$HD_OUT" 'OLD STALE REPLY' "only the fresh reply is returned"
}

case_model_selection() {
  zcode_setup
  hd_run spawn w1 worker --model local/vendor/model
  assert_eq 0 "$HD_RC" "spawn with a changed model"
  local state; state="$(zstate w1)"
  assert_jq '.config.defaultModelSelection == {providerId:"local",modelId:"vendor/model"}' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "a changed model clears stale reasoning"
  hd_run spawn w2 worker --model local/base
  assert_eq 0 "$HD_RC" "spawn with the provider default model"
  state="$(zstate w2)"
  assert_jq '.config.defaultModelSelection == {providerId:"local",modelId:"base",options:{reasoningLevel:"low"}}' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "the same model keeps its reasoning"
  hd_run spawn w3 worker
  assert_eq 0 "$HD_RC" "spawn without a model"
  state="$(zstate w3)"
  assert_jq '.config.defaultModelSelection == {providerId:"local",modelId:"base",options:{reasoningLevel:"low"}}' \
    "$(cat "$state/home/.zcode/v2/provider_config.json")" "the provider default model is kept"
}

case_spawn_preserves_state() {
  zcode_setup
  cat > "$FAKE_DIR/on-pane-run" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
herdr pane report-agent --source llstack:zcode --agent zcode --state working "$1" >/dev/null 2>&1 || true
SCRIPT
  chmod +x "$FAKE_DIR/on-pane-run"
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "spawn with an early hook report"
  assert_jq '.result.agent.agent_status == "working"' "$(herdr agent get "$(zc_pane w1)")" "spawn keeps a hook state"
  assert_not_contains "$(cat "$FAKE_DIR/calls.log")" $'--state\tidle' "spawn does not overwrite a hook state"
}

case_roles() {
  zcode_setup
  local state tools
  hd_run spawn sc scout
  assert_eq 0 "$HD_RC" "scout spawn"
  state="$(zstate sc)"
  tools="$(cat "$state/disallowed")"
  assert_contains "$tools" 'Agent Task AskUserQuestion EnterPlanMode ExitPlanMode' "scout base tools"
  assert_contains "$tools" 'Edit ApplyPatch' "scout edit tools"
  assert_not_contains "$tools" ' Bash ' "scout keeps Bash"
  hd_run spawn rs researcher
  assert_eq 0 "$HD_RC" "researcher spawn"
  state="$(zstate rs)"
  tools="$(cat "$state/disallowed")"
  assert_contains "$tools" 'Bash Edit ApplyPatch' "researcher tools"
}


case_reviewer_role() {
  zcode_setup
  local state tools
  hd_run spawn rv reviewer
  assert_eq 0 "$HD_RC" "reviewer spawn"
  state="$(zstate rv)"
  tools="$(cat "$state/disallowed")"
  assert_contains "$tools" 'Edit ApplyPatch' "reviewer edit tools"
  assert_not_contains "$tools" ' Bash ' "reviewer keeps Bash"
}

case_ask_in_flight() {
  zcode_setup
  hd_run spawn w1 worker
  assert_eq 0 "$HD_RC" "zcode spawn"
  local state; state="$(zstate w1)"
  write_on_enter <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
pane="$1"
source "$HD_TEST_LIB"
state="$(zcode_state_dir w1)"
jq -nc --arg s sess-busy --arg t turn-busy --arg p "$(<"$state/line")" \
  '{hookEventName:"UserPromptSubmit",sessionId:$s,turnId:$t,prompt:$p}' >> "$state/events.jsonl"
SCRIPT
  hd_run ask w1 'First brief.' --timeout 300
  assert_contains "$HD_OUT" 'STATUS: still_working' "first ask times out"
  local first_request; first_request="$(<"$state/request")"
  hd_run ask w1 'First brief.' --timeout 300
  assert_eq 1 "$HD_RC" "second ask while the first is in flight"
  assert_contains "$HD_OUT" 'hd wait w1' "in-flight diagnostic"
  assert_eq 1 "$(send_count "$(zc_pane w1)")" "no second submission"
  assert_eq "$first_request" "$(<"$state/request")" "request kept"
  zc_stop_event "$state" sess-busy turn-busy $'late reply\nSTATUS: done'
  zc_completed_log "$state" sess-busy turn-busy
  hd_run wait w1 --timeout 3000
  assert_eq 0 "$HD_RC" "wait after the refused ask"
  assert_contains "$HD_OUT" 'late reply' "first ask still settles"
}

run_case zcode_invalid_name case_invalid_name
run_case zcode_spawn_tui case_spawn_tui
run_case zcode_spawn_preserves_state case_spawn_preserves_state
run_case zcode_model_selection case_model_selection
run_case zcode_roles case_roles
run_case zcode_reviewer_role case_reviewer_role
run_case zcode_spawn_failure case_spawn_failure
run_case zcode_preflight case_preflight
run_case zcode_wait_stop_before_log case_wait_stop_before_log
run_case zcode_wait_deadline case_wait_deadline
run_case zcode_launcher_exit case_launcher_exit
run_case zcode_stale_launcher_exit case_stale_launcher_exit
run_case zcode_pi_context_newline case_pi_context_newline
run_case zcode_pi_old_mark case_pi_old_mark
run_case zcode_spawn_fresh case_spawn_fresh
run_case zcode_ask_request case_ask_request
run_case zcode_followup case_followup
run_case zcode_wait_timeout_then_wait case_wait_timeout_then_wait
run_case zcode_wait_blocked case_wait_blocked
run_case zcode_wait_stale_turns case_wait_stale_turns
run_case zcode_wait_no_reply case_wait_no_reply
run_case zcode_provider_retry case_provider_retry
run_case zcode_provider_failure_twice case_provider_failure_twice
run_case zcode_fallback_to_pi case_fallback_to_pi
run_case zcode_cancelled case_cancelled
run_case zcode_stop_resume case_stop_resume
run_case zcode_resume_after_tui_exit case_resume_after_tui_exit
run_case zcode_resume_manual_session case_resume_manual_session
run_case zcode_resume_empty case_resume_empty
run_case zcode_paths_quotes case_paths_quotes
run_case zcode_ask_in_flight case_ask_in_flight
