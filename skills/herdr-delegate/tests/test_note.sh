#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_note_journal() {
  hd_run note w1 "root cause"
  assert_eq 0 "$HD_RC" "hd note"
  local journal="$XDG_CACHE_HOME/herdr-delegate/journal.jsonl" entry
  assert_exists "$journal" "journal"
  assert_eq 1 "$(( $(wc -l < "$journal") ))" "journal line count"
  entry="$(jq -c 'select(.event == "note")' "$journal")"
  assert_jq '.event == "note"' "$entry" "journal event"
  assert_jq '.text == "root cause"' "$entry" "journal text"
  assert_jq '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$")' "$entry" "journal ts"
}

run_case note_journal case_note_journal
