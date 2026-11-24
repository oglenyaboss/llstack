#!/usr/bin/env bash

zcode_dir() { echo "$(run_dir)/$1.zcode"; }
zcode_home() { echo "$(zcode_dir "$1")/home"; }
zcode_pane() { cat "$(zcode_dir "$1")/pane" 2>/dev/null; }
zcode_events() { echo "$(zcode_dir "$1")/events.jsonl"; }
zcode_request_file() { echo "$(zcode_dir "$1")/request"; }
zcode_line_file() { echo "$(zcode_dir "$1")/line"; }
zcode_turn_file() { echo "$(zcode_dir "$1")/turn"; }
zcode_settled_file() { echo "$(zcode_dir "$1")/settled"; }
zcode_in_flight() { [[ -f "$(zcode_request_file "$1")" && ! -f "$(zcode_settled_file "$1")" ]]; }

zcode_exit_file() {
  local dir pid
  dir="$(zcode_dir "$1")"
  pid="$(cat "$dir/launcher-pid" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s/launcher-exit.%s\n' "$dir" "$pid"
}

zcode_validate_name() {
  [[ "$1" =~ ^[a-z][a-z0-9_-]*$ && ${#1} -le 27 ]] || die "zcode agent name must be 1-27 lowercase letters, digits, underscores or hyphens, starting with a letter"
}

zcode_now_ms() {
  local value
  if value="$(date +%s%3N 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if value="$(gdate +%s%3N 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  printf '%s000\n' "$(date +%s)"
}

zcode_live_pane() {
  local name="$1" pane
  pane="$(zcode_pane "$name")" || return 1
  [[ -n "$pane" ]] || return 1
  herdr pane get "$pane" >/dev/null 2>&1 || return 1
  printf '%s\n' "$pane"
}

zcode_resolve_bin() {
  local bin
  bin="$(command -v zcode 2>/dev/null)" || die "zcode is not on PATH"
  [[ "$bin" == /* ]] || bin="$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")"
  [[ -x "$bin" ]] || die "zcode is not executable: $bin"
  printf '%s\n' "$bin"
}

zcode_source_provider() {
  printf '%s\n' "${ZCODE_PERSONAL_PROVIDER_CONFIG_FILE:-${ZCODE_DATA_BASE_DIR:-$HOME}/.zcode/v2/provider_config.json}"
}

zcode_valid_model() {
  local model="$1"
  [[ -z "$model" ]] && return 0
  [[ "$model" == */* && "$model" != /* && "$model" != */ ]] || return 1
  [[ "${model#*/}" != /* ]] || return 1
}

zcode_validate_model() {
  zcode_valid_model "$1" || die "zcode model must be providerId/modelId"
}

zcode_render_provider() {
  local source="$1" model="$2" thinking="$3" provider="" model_id=""
  if [[ -n "$model" ]]; then
    provider="${model%%/*}"
    model_id="${model#*/}"
  fi
  jq -e --arg provider "$provider" --arg model_id "$model_id" --arg thinking "$thinking" '
    select(.schemaVersion == 1 and (.config | type) == "object")
    | .config as $current
    | (($current.defaultModelSelection.providerId? // "") == $provider
       and ($current.defaultModelSelection.modelId? // "") == $model_id) as $same_model
    | if $provider != "" then
        .config.defaultModelSelection = (
          {providerId: $provider, modelId: $model_id}
          + (if $thinking != "" then
               {options: ((if $same_model and (($current.defaultModelSelection.options? // null) | type) == "object"
                           then $current.defaultModelSelection.options else {} end)
                          + {reasoningLevel: $thinking})}
             elif ($same_model
                   and (($current.defaultModelSelection.options? // null) | type) == "object")
             then
               {options: $current.defaultModelSelection.options}
             else
               {}
             end)
        )
      elif $thinking != "" then
        .config.defaultModelSelection.options.reasoningLevel = $thinking
      else . end
    | select((.config.defaultModelSelection.providerId | type) == "string" and (.config.defaultModelSelection.providerId | length) > 0)
    | select((.config.defaultModelSelection.modelId | type) == "string" and (.config.defaultModelSelection.modelId | length) > 0)
    | (.config.defaultModelSelection.providerId) as $selected
    | select(
        ((.config.providerConfigRules.providerRules? // []) | type) == "array"
        and any(.config.providerConfigRules.providerRules[];
             .providerId == $selected
             and ((.config.access? // {}).type? // "") == "api-key"
             and (((.config.access? // {}).apiKey? // "") | type) == "string"
             and (((.config.access? // {}).apiKey // "") | gsub("^\\s+|\\s+$"; "") | length) > 0
             and ((.config.api? // {}) | type) == "object"
             and (((.config.api? // {}).baseUrl? // "") | type) == "string"
             and (((.config.api? // {}).baseUrl // "") | gsub("^\\s+|\\s+$"; "") | length) > 0)
      )
  ' "$source"
}

zcode_write_private() {
  local path="$1" value="$2"
  (umask 077; printf '%s\n' "$value" > "$path") || return 1
  chmod 600 "$path"
}

zcode_resolved_model() {
  jq -r '.config.defaultModelSelection | "\(.providerId)/\(.modelId)"' "$1" 2>/dev/null
}

zcode_resolved_thinking() {
  jq -r '.config.defaultModelSelection.options.reasoningLevel // empty' "$1" 2>/dev/null
}

zcode_disallowed() {
  case "$1" in
    scout|reviewer) echo 'Agent Task AskUserQuestion EnterPlanMode ExitPlanMode Edit ApplyPatch' ;;
    researcher) echo 'Agent Task AskUserQuestion EnterPlanMode ExitPlanMode Bash Edit ApplyPatch' ;;
    *) echo 'Agent Task AskUserQuestion EnterPlanMode ExitPlanMode' ;;
  esac
}

zcode_write_runtime_config() {
  local name="$1" dir config profile_home
  dir="$(zcode_dir "$name")"
  profile_home="$(zcode_home "$name")"
  config="$profile_home/.zcode/cli/config.json"
  (umask 077; jq -n --arg hook "$SKILL_DIR/zcode-hook" --arg state "$dir" '
    def hook: {hooks: [{type: "process", command: "bash", args: [$hook, $state], timeoutMs: 5000}]};
    {
      features: {mcp: false, subagent: false, memory: false, skill: false},
      memory: {use: false},
      plugins: {enabled: false},
      skills: {enabled: false},
      hooks: {
        enabled: true,
        events: {
          SessionStart: [hook], UserPromptSubmit: [hook], PreToolUse: [hook],
          PermissionRequest: [hook], PostToolUse: [hook], PostToolUseFailure: [hook], Stop: [hook]
        }
      }
    }
  ' > "$config") || die "could not write the private ZCode config"
  chmod 600 "$config"
}

zcode_write_context() {
  local name="$1" role="$2" cwd="$3" dir file
  dir="$(zcode_dir "$name")"
  (umask 077; {
    while IFS= read -r -d '' file; do
      [[ -n "$file" ]] || continue
      cat "$file"
      printf '\n'
    done < <(project_context_files "$cwd")
    cat "$SKILL_DIR/roles/$role.md"
    printf '\n'
    cat "$SKILL_DIR/roles/_envelope.md"
  } > "$dir/context.md") || die "could not write the ZCode context"
  chmod 600 "$dir/context.md"
}

zcode_write_common_state() {
  local name="$1" role="$2" cwd="$3" bin="$4" dir
  dir="$(zcode_dir "$name")"
  zcode_write_private "$dir/zcode-bin" "$bin" || die "could not write the ZCode launcher state"
  zcode_write_private "$dir/cwd" "$cwd" || die "could not write the ZCode launcher state"
  zcode_write_private "$dir/disallowed" "$(zcode_disallowed "$role")" || die "could not write the ZCode launcher state"
  zcode_write_runtime_config "$name"
  zcode_write_context "$name" "$role" "$cwd"
}

zcode_launch_pane() {
  local name="$1" dir pane command
  dir="$(zcode_dir "$name")"
  pane="$(zcode_pane "$name")"
  rm -f "$dir/launcher-pid"
  printf -v command '%q %q' "$SKILL_DIR/zcode-launch" "$dir"
  herdr pane run "$pane" "$command" >/dev/null || die "could not start the ZCode TUI"
}

zcode_launcher_exit() {
  cat "$(zcode_exit_file "$1")" 2>/dev/null || true
}

zcode_wait_ready() {
  local pane="$1"
  if ! herdr pane wait-output "$pane" --match 'Type a prompt' --timeout 60000 >/dev/null 2>&1; then
    echo "spawn: zcode did not become ready; screen:" >&2
    herdr pane read "$pane" --source visible >&2 || true
    exit 1
  fi
}

zcode_report() {
  local pane="$1" state="$2"
  [[ -n "$pane" ]] || return 0
  herdr pane report-agent --source llstack:zcode --agent zcode --state "$state" "$pane" >/dev/null 2>&1 || true
}

zcode_after_ready() {
  local name="$1" pane="$2" status=""
  if [[ -f "$(zcode_exit_file "$name")" ]]; then
    echo "spawn: zcode exited during startup; marker: $(zcode_exit_file "$name")" >&2
    herdr pane read "$pane" --source visible >&2 || true
    exit 1
  fi
  status="$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)"
  case "$status" in
    idle|working|blocked|done) ;;
    *) zcode_report "$pane" idle ;;
  esac
  herdr agent rename "$pane" "$(target "$name")" >/dev/null 2>&1 || true
}

zcode_session_id() {
  local name="$1" dir events
  dir="$(zcode_dir "$name")"
  events="$dir/events.jsonl"
  [[ -f "$events" ]] || return 0
  jq -Rrn '[inputs | fromjson? // empty | .sessionId? // empty | strings] | last // empty' < "$events"
}

zcode_save_session() {
  local name="$1" dir id
  dir="$(zcode_dir "$name")"
  id="$(zcode_session_id "$name")"
  if [[ -n "$id" ]]; then
    zcode_write_private "$dir/session-id" "$id" || die "could not save the ZCode session"
  else
    rm -f "$dir/session-id"
  fi
}

spawn_zcode() {
  local name="$1" role="$2" cwd="$3" model="${4:-}" thinking="${5:-}" session="$6"
  local slot="${7:-$2}" fallback="${8:-[]}"
  local bin source dir profile_home rd pane provider_tmp model_id
  zcode_validate_name "$name"
  bin="$(zcode_resolve_bin)"
  [[ -f "$SKILL_DIR/roles/$role.md" ]] || die "no role file: $SKILL_DIR/roles/$role.md"
  role_tools "$role" >/dev/null
  [[ -x "$SKILL_DIR/zcode-launch" ]] || die "missing ZCode launcher: $SKILL_DIR/zcode-launch"
  [[ -z "$session" ]] || die "zcode sessions are not imported with --session; use hd resume"
  zcode_validate_model "$model"
  source="$(zcode_source_provider)"
  [[ -r "$source" ]] || die "configure ZCode first: missing personal provider config"
  provider_tmp="$(mktemp "${TMPDIR:-/tmp}/hd-zcode-provider.XXXXXX")"
  if ! zcode_render_provider "$source" "$model" "$thinking" > "$provider_tmp" 2>/dev/null; then
    rm -f "$provider_tmp"
    die "invalid ZCode personal provider config: need a default model and a directly configured API-key provider"
  fi
  model_id="$(zcode_resolved_model "$provider_tmp")"
  if [[ -z "$model_id" ]]; then
    rm -f "$provider_tmp"
    die "invalid ZCode personal provider config: need a default model and a directly configured API-key provider"
  fi

  rd="$(run_dir)"
  dir="$(zcode_dir "$name")"
  profile_home="$(zcode_home "$name")"
  if [[ -f "$dir/pane" ]] && herdr pane get "$(cat "$dir/pane")" >/dev/null 2>&1; then
    rm -f "$provider_tmp"
    die "$name already exists; stop it first"
  fi
  if ! rm -rf "$dir"; then
    rm -f "$provider_tmp"
    die "could not reset the ZCode state"
  fi

  (umask 077; mkdir -p "$profile_home/.zcode/v2" "$profile_home/.zcode/cli" "$dir/db" "$dir/storage" "$dir/log" "$dir/requests")
  chmod 700 "$dir" "$profile_home" "$profile_home/.zcode" "$profile_home/.zcode/v2" "$profile_home/.zcode/cli"
  mv "$provider_tmp" "$profile_home/.zcode/v2/provider_config.json"
  chmod 600 "$profile_home/.zcode/v2/provider_config.json"
  zcode_write_private "$dir/model" "$(zcode_resolved_model "$profile_home/.zcode/v2/provider_config.json")" || die "could not write the ZCode state"
  zcode_write_private "$dir/thinking" "$(zcode_resolved_thinking "$profile_home/.zcode/v2/provider_config.json")" || die "could not write the ZCode state"
  zcode_write_common_state "$name" "$role" "$cwd" "$bin"
  rm -f "$dir/session-id" "$dir/request" "$dir/line" "$dir/turn" "$dir/settled"

  pane="$(place_pane "$rd" "$cwd")"
  record_spawn "$rd" "$pane" "$name" "$role" zcode "$model" "$cwd" "$slot" "$thinking" "$fallback"
  zcode_write_private "$dir/pane" "$pane" || die "could not write the ZCode state"
  zcode_launch_pane "$name"
  zcode_wait_ready "$pane"
  zcode_after_ready "$name" "$pane"
  echo "spawned $name role=$role agent=zcode pane=$pane model=$model_id cwd=$cwd"
}

resume_zcode() {
  local name="$1"; shift
  zcode_validate_name "$name"
  local cwd="" model="" thinking="" dir profile_home rd role bin saved_model saved_thinking pane session_id
  local saved_slot saved_fallback
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --thinking) thinking="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  config_json "$(config_path)" >/dev/null
  rd="$(run_dir)"
  dir="$(zcode_dir "$name")"
  profile_home="$(zcode_home "$name")"
  [[ -d "$profile_home/.zcode" && -f "$rd/$name.role" ]] || die "no stopped session for $name"
  [[ -f "$profile_home/.zcode/v2/provider_config.json" ]] || die "no stopped session for $name"
  jq -e . "$profile_home/.zcode/v2/provider_config.json" >/dev/null 2>&1 || die "no stopped session for $name"
  if [[ -f "$dir/pane" ]] && herdr agent get "$(cat "$dir/pane")" >/dev/null 2>&1; then
    die "$name is still running; stop it first"
  fi
  role="$(cat "$rd/$name.role")"
  [[ -f "$SKILL_DIR/roles/$role.md" ]] || die "no role file: $SKILL_DIR/roles/$role.md"
  role_tools "$role" >/dev/null
  bin="$(zcode_resolve_bin)"
  saved_model="$(cat "$dir/model" 2>/dev/null || true)"
  saved_thinking="$(cat "$dir/thinking" 2>/dev/null || true)"
  [[ -z "$saved_model" ]] && saved_model="$(zcode_resolved_model "$profile_home/.zcode/v2/provider_config.json")"
  [[ -z "$saved_thinking" ]] && saved_thinking="$(zcode_resolved_thinking "$profile_home/.zcode/v2/provider_config.json")"
  if [[ -n "$model" && "$model" != "$saved_model" ]]; then
    die "zcode resume keeps the persisted model ($saved_model); change it with /model in the TUI"
  fi
  if [[ -n "$thinking" && "$thinking" != "$saved_thinking" ]]; then
    die "zcode resume keeps the persisted thinking ($saved_thinking); change it in the TUI"
  fi
  cwd="${cwd:-$(cat "$dir/cwd" 2>/dev/null || echo "$PWD")}"
  cwd="$(cd "$cwd" 2>/dev/null && pwd)" || die "no such directory: $cwd"

  zcode_write_common_state "$name" "$role" "$cwd" "$bin"
  rm -f "$dir/request" "$dir/line" "$dir/turn" "$dir/settled" "$rd/$name.mark"
  session_id="$(zcode_session_id "$name")"
  if [[ -n "$session_id" ]]; then
    zcode_write_private "$dir/session-id" "$session_id" || die "could not save the ZCode session"
  fi

  pane="$(place_pane "$rd" "$cwd")"
  saved_slot="$(cat "$rd/$name.slot" 2>/dev/null || cat "$rd/$name.role")"
  saved_fallback="$(cat "$rd/$name.fallback" 2>/dev/null || printf '[]\n')"
  record_spawn "$rd" "$pane" "$name" "$role" zcode "$saved_model" "$cwd" "$saved_slot" "$saved_thinking" "$saved_fallback"
  zcode_write_private "$dir/pane" "$pane" || die "could not write the ZCode state"
  zcode_launch_pane "$name"
  zcode_wait_ready "$pane"
  zcode_after_ready "$name" "$pane"
  echo "spawned $name role=$role agent=zcode pane=$pane model=$saved_model cwd=$cwd"
}

zcode_new_request() {
  local name="$1" message="$2" tag="$3" dir rd events seq path line offset
  tag="${tag%.md}"
  dir="$(zcode_dir "$name")"
  rd="$(run_dir)"
  mkdir -p "$dir/requests"
  chmod 700 "$dir/requests"
  seq=$(( $(find "$dir/requests" -maxdepth 1 -type f | wc -l) + 1 ))
  path="$dir/requests/$(printf '%02d' "$seq")-$tag.md"
  (umask 077; printf '%s\n' "$message" > "$path") || die "could not save the ZCode request"
  chmod 600 "$path"
  printf '%s' "$path" > "$dir/request"
  line="Read the brief in $(jq -Rn --arg path "$path" '$path') and execute it. End with the report envelope."
  printf '%s' "$line" > "$dir/line"
  rm -f "$dir/turn" "$dir/settled"
  events="$(zcode_events "$name")"
  if [[ -f "$events" ]]; then offset="$(wc -l < "$events")"; else offset=0; fi
  offset="${offset//[[:space:]]/}"
  printf '%s\n%s\n' "$events" "$offset" > "$rd/$name.mark"
}

zcode_send_line() {
  local name="$1" pane line
  pane="$(zcode_live_pane "$name")" || die "zcode TUI for $name is not running"
  line="$(cat "$(zcode_line_file "$name")" 2>/dev/null || true)"
  [[ -n "$line" ]] || die "no ZCode request for $name"
  herdr pane send-text "$pane" "$line" >/dev/null 2>&1 || die "could not deliver the ZCode request"
  herdr pane send-keys "$pane" enter >/dev/null 2>&1 || die "could not submit the ZCode request"
}

zcode_find_prompt() {
  local events="$1" request="$2" offset="$3"
  [[ -f "$events" ]] || return 0
  jq -Rrn --arg request "$request" --argjson offset "$offset" '
    [inputs] | .[$offset:] | map(fromjson? // empty)
    | map(select(.hookEventName == "UserPromptSubmit"
                 and (.sessionId? | type) == "string"
                 and (.turnId? | type) == "string"
                 and ((.prompt // "") | contains($request))))
    | first // empty
    | if . == null then empty else [.sessionId, .turnId] | @tsv end
  ' < "$events"
}

zcode_stop_record() {
  local events="$1" session="$2" turn="$3"
  [[ -f "$events" ]] || { printf '%s\n' '{"found":false}'; return 0; }
  jq -Rrn --arg session "$session" --arg turn "$turn" '
    [inputs | fromjson? // empty
     | select(.hookEventName == "Stop" and .sessionId == $session and .turnId == $turn)]
    | last // empty
    | if . == null then {found: false} else {found: true, text: (.responseText // null)} end
  ' < "$events"
}

# ponytail: structured-log settlement is tested on zcode 0.17.1; replace it with a terminal error hook when upstream provides one.
zcode_log_outcome() {
  local name="$1" session="$2" turn="$3" dir files=()
  dir="$(zcode_dir "$name")"
  shopt -s nullglob
  files=("$dir"/log/*.jsonl)
  shopt -u nullglob
  (( ${#files[@]} )) || return 0
  jq -Rrn --arg session "$session" --arg turn "$turn" '
    [inputs | fromjson? // empty
     | select(.sessionId == $session and .turnId == $turn)
     | select(.event == "turn.failed" or .event == "turn.completed")]
    | if any(.[]; .event == "turn.failed" and .status == "cancelled") then "cancelled"
      elif any(.[]; .event == "turn.failed") then "failed"
      elif any(.[]; .event == "turn.completed") then "completed"
      else "" end
  ' "${files[@]}"
}

zcode_wait_turn() {
  local name="$1" timeout="$2" dir events request mark_file offset=0 mark_session=""
  local session="" turn="" pair="" status="" outcome="" stop="" deadline now remaining delay
  dir="$(zcode_dir "$name")"
  events="$(zcode_events "$name")"
  request="$(cat "$(zcode_request_file "$name")" 2>/dev/null || true)"
  [[ -n "$request" ]] || { printf 'no_request\n'; return 0; }
  mark_file="$(run_dir)/$name.mark"
  if [[ -f "$mark_file" ]]; then
    { IFS= read -r -d '' mark_session; IFS= read -r -d '' offset; } < <(session_mark_read "$mark_file")
    [[ "$mark_session" == "$events" ]] || offset=0
  fi
  [[ "$offset" =~ ^[0-9]+$ ]] || offset=0
  deadline=$(( $(zcode_now_ms) + timeout ))
  while :; do
    status="$(agent_status "$name" 2>/dev/null || true)"
    if [[ "$status" == blocked ]]; then
      printf 'blocked\n'
      return 0
    fi
    if [[ -z "$session" ]]; then
      pair="$(zcode_find_prompt "$events" "$request" "$offset")"
      if [[ -n "$pair" ]]; then
        IFS=$'\t' read -r session turn <<< "$pair"
        printf '%s %s\n' "$session" "$turn" > "$(zcode_turn_file "$name")"
        zcode_write_private "$dir/session-id" "$session" || true
      fi
    fi
    if [[ -n "$session" && -n "$turn" ]]; then
      outcome="$(zcode_log_outcome "$name" "$session" "$turn")"
      case "$outcome" in
        failed)
          printf 'failed\n' > "$(zcode_settled_file "$name")"
          zcode_report "$(zcode_pane "$name")" idle
          printf 'failed\n'
          return 0
          ;;
        cancelled)
          printf 'cancelled\n' > "$(zcode_settled_file "$name")"
          zcode_report "$(zcode_pane "$name")" idle
          printf 'cancelled\n'
          return 0
          ;;
        completed)
          stop="$(zcode_stop_record "$events" "$session" "$turn")"
          if [[ "$(jq -r '.found' <<< "$stop")" == true ]]; then
            if [[ "$(jq -r '.text == null or (.text | length) == 0' <<< "$stop")" == true ]]; then
              printf 'no_reply\n' > "$(zcode_settled_file "$name")"
              printf 'no_reply\n'
            else
              printf 'completed\n' > "$(zcode_settled_file "$name")"
              printf 'completed\n'
            fi
            return 0
          fi
          printf 'no_reply\n' > "$(zcode_settled_file "$name")"
          printf 'no_reply\n'
          return 0
          ;;
      esac
    fi
    if [[ -f "$(zcode_exit_file "$name")" ]]; then
      printf 'exited\n' > "$(zcode_settled_file "$name")"
      printf 'exited\n'
      return 0
    fi
    now="$(zcode_now_ms)"
    (( now >= deadline )) && break
    remaining=$((deadline - now))
    (( remaining > 100 )) && remaining=100
    printf -v delay '%d.%03d' "$((remaining / 1000))" "$((remaining % 1000))"
    sleep "$delay"
  done
  printf 'timeout\n'
}

zcode_reply_text() {
  local name="$1" dir events session turn settled
  dir="$(zcode_dir "$name")"
  events="$dir/events.jsonl"
  settled="$(cat "$(zcode_settled_file "$name")" 2>/dev/null || true)"
  [[ "$settled" == completed ]] || return 0
  [[ -f "$dir/turn" && -f "$events" ]] || return 0
  read -r session turn < "$dir/turn" || return 0
  [[ -n "$session" && -n "$turn" ]] || return 0
  jq -Rrn --arg session "$session" --arg turn "$turn" '
    [inputs | fromjson? // empty
     | select(.hookEventName == "Stop" and .sessionId == $session and .turnId == $turn)]
    | last // empty
    | .responseText // empty
  ' < "$events"
}

zcode_provider_error() {
  local name="$1" dir settled
  dir="$(zcode_dir "$name")"
  settled="$(cat "$(zcode_settled_file "$name")" 2>/dev/null || true)"
  [[ "$settled" == failed ]] || return 0
  printf 'ZCode turn failed (diagnostics: %s)\n' "$dir/log"
}

zcode_screen_tail() {
  local pane
  if pane="$(zcode_live_pane "$1")"; then
    herdr pane read "$pane" --source visible
  else
    printf 'SCREEN TAIL\n'
  fi
}
