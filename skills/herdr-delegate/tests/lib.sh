#!/usr/bin/env bash
# Shared helpers for the hd tests. ROOT is this skill's directory, so the suite
# runs from a copy, a clone, or a symlinked skill directory.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HD="$ROOT/hd"
CASE_NAME=""
TIMEOUT="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

t_fail() { printf 'FAIL %s: %s\n' "$CASE_NAME" "$*"; exit 1; }

assert_eq() {
  local expected="$1" actual="$2" label="${3:-value}"
  [[ "$expected" == "$actual" ]] || t_fail "$label: expected [$expected], got [$actual]"
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-output}"
  [[ "$haystack" == *"$needle"* ]] || t_fail "$label: missing [$needle] in [${haystack//$'\n'/ | }]"
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-output}"
  [[ "$haystack" != *"$needle"* ]] || t_fail "$label: unexpected [$needle]"
}

assert_file_contains() {
  local file="$1" needle="$2" label="${3:-$1}"
  [[ -f "$file" ]] || t_fail "$label: file does not exist"
  assert_contains "$(cat "$file")" "$needle" "$label"
}

assert_file_not_contains() {
  local file="$1" needle="$2" label="${3:-$1}"
  [[ -f "$file" ]] || t_fail "$label: file does not exist"
  assert_not_contains "$(cat "$file")" "$needle" "$label"
}

assert_exists() {
  local path="$1" label="${2:-$1}"
  [[ -e "$path" ]] || t_fail "$label: does not exist"
}

assert_after() {
  local text="$1" first="$2" second="$3" line found=0
  while IFS= read -r line; do
    if (( found )); then
      [[ "$line" == "$second" ]] || t_fail "line after [$first] is [$line], expected [$second]"
      return 0
    fi
    [[ "$line" == "$first" ]] && found=1
  done <<< "$text"
  t_fail "missing line [$first]"
}

assert_jq() {
  local expr="$1" input="$2" label="${3:-jq}"
  jq -e "$expr" >/dev/null 2>&1 <<< "$input" || t_fail "$label: jq [$expr] failed for [$input]"
}

assert_calls_nonempty() {
  [[ -s "$FAKE_DIR/calls.log" ]] || t_fail "fake herdr received no calls"
}

hd_run() {
  set +e
  HD_OUT="$("$HD" "$@" 2>&1)"
  HD_RC=$?
  set -e
}

hd_config() { printf '%s\n' "$1" > "$HD_CONFIG"; }

case_setup() {
  CASE_TMP="$1"
  export FAKE_DIR="$CASE_TMP/fake"
  export XDG_CACHE_HOME="$CASE_TMP/cache"
  export PI_CODING_AGENT_DIR="$CASE_TMP/pi"
  export HD_TEST_LIB="$ROOT/tests/lib.sh"
  export HD_CONFIG="$CASE_TMP/hd-config.json"
  mkdir -p "$FAKE_DIR" "$XDG_CACHE_HOME" "$PI_CODING_AGENT_DIR" "$CASE_TMP/work/src"
  export PATH="$ROOT/tests/fake:$PATH"
  export HERDR_ENV=1
  export HERDR_PANE_ID=test:p0
  export HERDR_WORKSPACE_ID=w1
  unset HD_HARNESS HD_MODEL HD_THINKING HD_PI_EXTENSIONS HERDR_BIN_PATH
  hd_config '{"default":{"harness":"pi","model":"prov/m1"}}'
  cd "$CASE_TMP/work"
  git init -q
  printf 'base\n' > src/a.txt
  git add src/a.txt
  git -c user.name=test -c user.email=test@example.com commit -qm init
}

run_case() {
  local name="$1" fn="$2" tmp last base="${TMPDIR:-/tmp}"
  CASE_NAME="$name"
  tmp="$(mktemp -d "${base%/}/hd-test.XXXXXX")"
  if ( set -euo pipefail; case_setup "$tmp"; "$fn" ) > "$tmp/log" 2>&1; then
    printf 'ok %s\n' "$name"
  else
    last="$(tail -n 1 "$tmp/log")"
    if [[ "$last" == FAIL* ]]; then
      printf '%s\n' "$last"
    else
      printf 'FAIL %s: %s\n' "$name" "${last:-case exited nonzero}"
    fi
    if [[ -n "${HD_TEST_VERBOSE:-}" ]]; then
      sed 's/^/    /' "$tmp/log" >&2
    fi
  fi
  rm -rf "$tmp"
}

turn() {
  local session="$1" text="$2" stop="${3:-stop}" err="${4:-}"
  jq -nc --arg text "$text" --arg stop "$stop" --arg err "$err" '
    {type:"message",
     message:({role:"assistant",
               content:[{type:"text",text:$text}],
               usage:{input:1000,cacheRead:2000,cacheWrite:0},
               stopReason:$stop}
              + (if $err == "" then {} else {errorMessage:$err} end))}' >> "$session"
}

payload_path() {
  sed -n 's/^OUTPUT_FILE: //p' "$FAKE_DIR/agents/$1/last-prompt" | tail -n 1
}

write_payload() {
  local path
  path="$(payload_path "$1")"
  [[ -n "$path" ]] || return 0
  mkdir -p "$(dirname "$path")"
  printf 'payload\n' > "$path"
}

write_hook() {
  cat > "$FAKE_DIR/on-prompt"
  chmod +x "$FAKE_DIR/on-prompt"
}

single_agent_dir() {
  local dirs=("$FAKE_DIR"/agents/*)
  [[ -e "${dirs[0]}" ]] || t_fail "fake herdr has no agents"
  (( ${#dirs[@]} == 1 )) || t_fail "expected one agent, found ${#dirs[@]}"
  printf '%s\n' "${dirs[0]}"
}

prompt_calls() {
  grep -c $'^agent\tprompt\t' "$FAKE_DIR/calls.log" 2>/dev/null || true
}

path_without() {
  local out="$CASE_TMP/path-without.$$.$RANDOM" dir name
  local -a dirs=()
  mkdir -p "$out"
  IFS=: read -ra dirs <<< "$PATH"
  for dir in "${dirs[@]}"; do
    [[ -n "$dir" && -d "$dir" ]] || continue
    ln -s "$dir"/* "$out"/ 2>/dev/null || true
  done
  for name in "$@"; do rm -f "$out/$name"; done
  printf '%s\n' "$out"
}

file_mode() {
  if stat -c %a "$1" >/dev/null 2>&1; then stat -c %a "$1"; else stat -f %Lp "$1"; fi
}

assert_mode() {
  local expected="$1" path="$2" label="${3:-$2}"
  assert_exists "$path" "$label"
  assert_eq "$expected" "$(file_mode "$path")" "$label mode"
}

zcode_state_dir() {
  local dirs=("$XDG_CACHE_HOME"/herdr-delegate/*/"$1.zcode")
  [[ -e "${dirs[0]}" ]] || t_fail "no zcode state dir for $1"
  (( ${#dirs[@]} == 1 )) || t_fail "expected one zcode state dir for $1, found ${#dirs[@]}"
  printf '%s\n' "${dirs[0]}"
}
