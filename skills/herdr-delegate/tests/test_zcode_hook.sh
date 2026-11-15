#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$ROOT/zcode-hook"

hook_setup() {
  STATE="${1:-$CASE_TMP/state}"
  mkdir -p -- "$STATE"
  export STATE HOOK_STATE="$STATE"
  export HERDR_BIN_PATH="$CASE_TMP/bin/herdr"
  mkdir -p -- "$CASE_TMP/bin"
  cat > "$HERDR_BIN_PATH" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
mkdir -p "$FAKE_DIR"
{
  first=1
  for arg in "$@"; do
    if (( first )); then printf '%s' "$arg"; first=0; else printf '\t%s' "$arg"; fi
  done
  printf '\n'
} >> "$FAKE_DIR/calls.log"
if [[ -n "${HOOK_STATE:-}" ]]; then
  if [[ -f "$HOOK_STATE/events.jsonl" ]]; then
    cp -- "$HOOK_STATE/events.jsonl" "$FAKE_DIR/events.at-report"
  else
    : > "$FAKE_DIR/events.at-report"
  fi
fi
printf 'fake herdr noise\n'
printf 'fake herdr error\n' >&2
[[ "${FAKE_HERDR_FAIL:-}" == 1 ]] && exit 1
exit 0
SH
  chmod +x "$HERDR_BIN_PATH"
}

run_hook() {
  local input="$1"
  set +e
  HOOK_OUT="$(printf '%s' "$input" | "$HOOK" "$STATE" 2>"$CASE_TMP/stderr")"
  HOOK_RC=$?
  set -e
}

log_json() { jq -s . "$STATE/events.jsonl"; }

snapshot_json() { jq -s . "$FAKE_DIR/events.at-report"; }

report_states() {
  awk -F'\t' '$1 == "pane" && $2 == "report-agent" {
    for (i = 1; i <= NF; i++) if ($i == "--state") print $(i + 1)
  }' "$FAKE_DIR/calls.log" 2>/dev/null
}

report_field() {
  local field="$1"
  awk -F'\t' -v field="$field" '$1 == "pane" && $2 == "report-agent" {
    for (i = 1; i <= NF; i++) if ($i == field) print $(i + 1)
  }' "$FAKE_DIR/calls.log" 2>/dev/null | tail -n 1
}

case_session_start() {
  hook_setup
  local context=$'# Role: worker\n\nProject rule: keep it brief.\n' input
  printf '%s' "$context" > "$STATE/context.md"
  input='{"hookEventName":"SessionStart","sessionId":"sess-1","turnId":"turn-1","traceId":"trace-1","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp","source":"startup"}'
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "session start exit"
  assert_eq '' "$(cat "$CASE_TMP/stderr")" "session start stderr"
  assert_jq '.hookSpecificOutput.hookEventName == "SessionStart"' "$HOOK_OUT" "session start output"
  assert_eq "$(jq -S -n --rawfile context "$STATE/context.md" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}')" "$(jq -S . <<< "$HOOK_OUT")" "session start context"
  assert_jq 'length == 1 and .[0].hookEventName == "SessionStart" and .[0].sessionId == "sess-1" and .[0].turnId == "turn-1" and .[0].traceId == "trace-1" and .[0].source == "startup"' "$(log_json)" "session start event"
  assert_jq 'length == 1 and .[0].hookEventName == "SessionStart"' "$(snapshot_json)" "session start event at report time"
  assert_eq idle "$(report_states)" "session start report state"
  assert_eq llstack:zcode "$(report_field --source)" "report source"
  assert_eq zcode "$(report_field --agent)" "report agent"
  assert_eq sess-1 "$(report_field --agent-session-id)" "report session id"
  assert_eq "$(cd "$STATE" && pwd -P)/events.jsonl" "$(report_field --agent-session-path)" "report session path"
}

case_prompt_stop() {
  hook_setup
  run_hook '{"hookEventName":"UserPromptSubmit","sessionId":"sess-2","turnId":"turn-2","traceId":"trace-2","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp","prompt":"Implement the task."}'
  assert_eq 0 "$HOOK_RC" "prompt exit"
  assert_eq '' "$HOOK_OUT" "prompt stdout"
  assert_jq 'length == 1 and .[0].hookEventName == "UserPromptSubmit" and .[0].prompt == "Implement the task."' "$(log_json)" "prompt event"
  assert_jq 'length == 1 and .[0].hookEventName == "UserPromptSubmit"' "$(snapshot_json)" "prompt event at report time"
  assert_eq working "$(report_states)" "prompt report state"

  local long input
  long="$(awk 'BEGIN { for (i = 0; i < 500; i++) printf "response line %04d: abcdefghijklmnopqrstuvwxyz\n", i }')"
  (( ${#long} > 10240 )) || t_fail "fixture response is only ${#long} bytes"
  input="$(jq -nc --arg text "$long" '{hookEventName: "Stop", sessionId: "sess-2", turnId: "turn-2", traceId: "trace-2", timestamp: "2026-01-01T00:00:01Z", cwd: "/tmp", responseText: $text, responsePreview: "response line 0000", stopHookActive: false, toolCallCount: 3}')"
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "stop exit"
  assert_eq '' "$HOOK_OUT" "stop stdout"
  assert_eq $'working\nidle' "$(report_states)" "report states"
  jq -se --arg text "$long" '
    length == 2
    and .[1].hookEventName == "Stop"
    and .[1].responseText == $text
    and (.[1].responseText | length) > 10240
    and .[1].responsePreview == "response line 0000"
    and (.[1] | has("usage") | not)
  ' "$STATE/events.jsonl" >/dev/null || t_fail "stop event does not preserve the full responseText"
  assert_jq 'length == 2 and .[1].hookEventName == "Stop"' "$(snapshot_json)" "stop event at report time"
}

case_tool_states() {
  hook_setup
  printf '%s\n' '{"hookEventName":"SessionStart","sessionId":"base"}' > "$STATE/events.jsonl"
  local before
  before="$(cat "$STATE/events.jsonl")"
  run_hook '{"hookEventName":"PermissionRequest","sessionId":"sess-3","toolName":"Bash","reason":"needs approval","requestId":"req-1"}'
  assert_eq 0 "$HOOK_RC" "permission exit"
  assert_eq '' "$HOOK_OUT" "permission stdout"
  assert_eq blocked "$(report_states)" "permission report state"
  assert_jq 'length == 1 and .[0].sessionId == "base"' "$(snapshot_json)" "permission does not log"
  run_hook '{"hookEventName":"PreToolUse","sessionId":"sess-3","toolName":"Bash","toolCallId":"call-1"}'
  assert_eq 0 "$HOOK_RC" "pre tool exit"
  run_hook '{"hookEventName":"PostToolUse","sessionId":"sess-3","toolName":"Bash","toolCallId":"call-1","toolResultPreview":"ok"}'
  assert_eq 0 "$HOOK_RC" "post tool exit"
  run_hook '{"hookEventName":"PostToolUseFailure","sessionId":"sess-3","toolName":"Bash","toolCallId":"call-2","error":{"type":"denied","message":"no"}}'
  assert_eq 0 "$HOOK_RC" "post tool failure exit"
  assert_eq $'blocked\nworking\nworking\nworking' "$(report_states)" "tool report states"
  assert_eq "$before" "$(cat "$STATE/events.jsonl")" "tool events do not log"
}

case_herdr_failure() {
  hook_setup
  printf 'Role context.\n' > "$STATE/context.md"
  local expected input
  expected="$(jq -S -n --rawfile context "$STATE/context.md" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}')"
  input='{"hookEventName":"SessionStart","sessionId":"sess-4","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp","source":"startup"}'
  unset HERDR_ENV
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "outside herdr exit"
  assert_eq "$expected" "$(jq -S . <<< "$HOOK_OUT")" "outside herdr context"
  assert_eq 1 "$(jq -s length "$STATE/events.jsonl")" "outside herdr event"
  [[ ! -e "$FAKE_DIR/calls.log" ]] || t_fail "outside herdr invoked herdr"

  export HERDR_ENV=1 FAKE_HERDR_FAIL=1
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "herdr failure exit"
  assert_eq "$expected" "$(jq -S . <<< "$HOOK_OUT")" "herdr failure keeps hook json"
  assert_eq 2 "$(jq -s length "$STATE/events.jsonl")" "herdr failure still logs"
  assert_exists "$FAKE_DIR/calls.log" "herdr failure was attempted"

  unset FAKE_HERDR_FAIL
  export HERDR_BIN_PATH="$CASE_TMP/missing herdr"
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "missing herdr exit"
  assert_eq "$expected" "$(jq -S . <<< "$HOOK_OUT")" "missing herdr keeps hook json"
  assert_eq 3 "$(jq -s length "$STATE/events.jsonl")" "missing herdr still logs"

  rm -f "$STATE/context.md"
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "missing context exit"
  assert_eq '' "$HOOK_OUT" "missing context stdout"
  assert_eq 4 "$(jq -s length "$STATE/events.jsonl")" "missing context still logs"
}

case_invalid_input() {
  hook_setup
  printf '%s\n' '{"hookEventName":"SessionStart","sessionId":"keep"}' '{"hookEventName":"Stop","sessionId":"keep","responseText":"old"}' > "$STATE/events.jsonl"
  local before input
  before="$(cat "$STATE/events.jsonl")"
  local -a inputs=(
    '{"hookEventName":"SessionStart","sessionId":"s","responseText":"TOP_SECRET"'
    '{"hookEventName":"UnknownEvent","sessionId":"s","responseText":"TOP_SECRET"}'
    '{"hookEventName":"SessionStart","responseText":"TOP_SECRET"}'
    '{"hookEventName":"UserPromptSubmit","sessionId":42}'
  )
  for input in "${inputs[@]}"; do
    run_hook "$input"
    [[ "$HOOK_RC" -ne 0 ]] || t_fail "invalid input exited 0: $input"
    assert_eq '' "$HOOK_OUT" "invalid input stdout"
    assert_contains "$(cat "$CASE_TMP/stderr")" 'invalid hook input' "invalid input stderr"
    assert_not_contains "$(cat "$CASE_TMP/stderr")" 'TOP_SECRET' "invalid input stderr"
    assert_eq "$before" "$(cat "$STATE/events.jsonl")" "invalid input log"
    [[ ! -e "$FAKE_DIR/calls.log" ]] || t_fail "invalid input invoked herdr"
  done
}

case_paths_and_aliases() {
  local state="$CASE_TMP/state dir with 'quotes'" other="$CASE_TMP/other repo"
  hook_setup "$state"
  printf 'Role context from a quoted path.\n' > "$STATE/context.md"
  mkdir -p -- "$other"
  git -C "$other" init -q
  cd "$other"
  local sid="sess 6'x" input expected
  input="$(jq -nc --arg sid "$sid" --arg cwd "$PWD" '{hook_event_name: "SessionStart", session_id: $sid, turn_id: "turn-6", trace_id: "trace-6", cwd: $cwd, timestamp: "2026-01-01T00:00:00Z", source: "resume"}')"
  expected="$(jq -S -n --rawfile context "$STATE/context.md" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}')"
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "quoted path exit"
  assert_eq "$expected" "$(jq -S . <<< "$HOOK_OUT")" "quoted path context"
  assert_jq 'length == 1 and .[0].hookEventName == "SessionStart" and .[0].sessionId == "sess 6'\''x" and .[0].turnId == "turn-6" and .[0].traceId == "trace-6" and .[0].source == "resume"' "$(log_json)" "aliases normalized"
  assert_jq '.[0] | (has("hook_event_name") | not) and (has("session_id") | not) and (has("turn_id") | not) and (has("trace_id") | not)' "$(log_json)" "snake aliases removed"
  assert_eq idle "$(report_states)" "quoted path report state"
  assert_eq "$sid" "$(report_field --agent-session-id)" "quoted path report session"
  assert_eq "$(cd "$STATE" && pwd -P)/events.jsonl" "$(report_field --agent-session-path)" "quoted path report path"

  input="$(jq -nc --arg sid "$sid" '{hook_event_name: "UserPromptSubmit", session_id: $sid, prompt: "continue"}')"
  run_hook "$input"
  assert_eq 0 "$HOOK_RC" "quoted prompt exit"
  assert_eq $'idle\nworking' "$(report_states)" "quoted prompt states"
  assert_jq 'length == 2 and .[1].hookEventName == "UserPromptSubmit" and .[1].sessionId == "sess 6'\''x" and .[1].prompt == "continue" and (.[1] | has("hook_event_name") | not)' "$(log_json)" "prompt aliases normalized"
}

run_case zcode_hook_session_start case_session_start
run_case zcode_hook_prompt_stop case_prompt_stop
run_case zcode_hook_tool_states case_tool_states
run_case zcode_hook_herdr_failure case_herdr_failure
run_case zcode_hook_invalid_input case_invalid_input
run_case zcode_hook_paths_and_aliases case_paths_and_aliases
