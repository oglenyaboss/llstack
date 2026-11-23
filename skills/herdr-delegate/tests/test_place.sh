#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

calls_matching() { grep -E "$1" "$FAKE_DIR/calls.log" || true; }

add_worktree() {
  git worktree add -q "$CASE_TMP/$1" -b "$1"
  git -C "$CASE_TMP/$1" rev-parse --show-toplevel
}

case_agent_lands_in_its_worktree_workspace() {
  local main wt
  main="$(git rev-parse --show-toplevel)"
  wt="$(add_worktree wt)"
  jq -n --arg main "$main" --arg wt "$wt" '{result:{workspaces:[
    {workspace_id:"w1",worktree:{checkout_path:$main}},
    {workspace_id:"w2",worktree:{checkout_path:$wt}}]}}' > "$FAKE_DIR/workspaces.json"

  hd_run spawn a worker --cwd "$wt"
  assert_eq 0 "$HD_RC" "hd spawn a in wt"
  hd_run spawn b worker
  assert_eq 0 "$HD_RC" "hd spawn b in main"

  local creates
  creates="$(calls_matching $'^tab\tcreate')"
  assert_contains "$creates" $'--workspace\tw2' "tab for the worktree agent"
  assert_contains "$creates" $'--workspace\tw1' "tab for the main checkout agent"
}

case_worktree_without_workspace_uses_lead_workspace() {
  local wt
  wt="$(add_worktree loose)"
  jq -n '{result:{workspaces:[{workspace_id:"w9",worktree:{checkout_path:"/elsewhere"}}]}}' > "$FAKE_DIR/workspaces.json"

  hd_run spawn a worker --cwd "$wt"
  assert_eq 0 "$HD_RC" "hd spawn a"
  assert_contains "$(calls_matching $'^tab\tcreate')" $'--workspace\tw1' "lead workspace"
}

case_tab_fills_two_by_two_then_opens_another() {
  local n
  for n in 1 2 3 4 5; do
    hd_run spawn "a$n" worker
    assert_eq 0 "$HD_RC" "hd spawn a$n"
  done
  local splits
  splits="$(calls_matching $'^pane\tsplit' | sed -E $'s/\t--cwd\t[^\t]*//; s/\t--no-focus//')"
  assert_eq $'pane\tsplit\t--pane\tp1\t--direction\tright
pane\tsplit\t--pane\tp1\t--direction\tdown
pane\tsplit\t--pane\tp2\t--direction\tdown' "$splits" "splits of the first tab"
  assert_eq 2 "$(calls_matching $'^tab\tcreate' | wc -l | tr -d ' ')" "tab creates"
  assert_eq "p5" "$(<"$FAKE_DIR/tabs/w1:t2")" "fifth agent opens the second tab"
}

case_stopped_agent_frees_its_slot() {
  local n
  for n in 1 2 3 4; do
    hd_run spawn "a$n" worker
    assert_eq 0 "$HD_RC" "hd spawn a$n"
  done
  herdr pane close p3
  hd_run spawn a5 worker
  assert_eq 0 "$HD_RC" "hd spawn a5"
  assert_eq 1 "$(calls_matching $'^tab\tcreate' | wc -l | tr -d ' ')" "tab creates"
  assert_contains "$(calls_matching $'^pane\tsplit' | tail -n 1)" $'--pane\tp1\t--direction\tdown' "refills the free slot"
}

run_case place_agent_in_worktree_workspace case_agent_lands_in_its_worktree_workspace
run_case place_unknown_worktree_in_lead_workspace case_worktree_without_workspace_uses_lead_workspace
run_case place_two_by_two_grid case_tab_fills_two_by_two_then_opens_another
run_case place_reuses_freed_slot case_stopped_agent_frees_its_slot
