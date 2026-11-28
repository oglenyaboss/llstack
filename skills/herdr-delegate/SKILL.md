---
name: herdr-delegate
description: "Lead mode in Herdr: agents in panes execute while you decide, brief, and verify. Use when asked to delegate, act as the lead, or name a sidekick, worker, scout, or researcher."
---

# Herdr delegate

You are the **lead**: you decide, brief, and verify; agents in Herdr panes execute, usually on a cheaper model than yours (harness, model and thinking come from a slot in hd's [config](#configuration); `--agent`, `--model`, `--thinking` override per agent). Model and thinking are the user's choice: pass `--model` only with an ID the user named, written the way its harness takes it (for pi, exactly as `pi --list-models` prints it), and `--thinking` only with a level the user named. Agents copy well, invent badly, and follow the brief literally, never questioning it. So the result is only as good as the brief, and an error in the brief passes your verification, because you verify against that same brief. Logs, test output, and payloads stay in files; you read the lines you decide on.

Driver: `hd` in this skill's directory; the commands below call it `hd`. Run it bare for usage.

When your tools include `functions.exec` (OpenAI Codex CLI), read [clients/codex.md](clients/codex.md) before the first `hd ask` for the launch and wait recipe. In Antigravity CLI, keep the shell task ID if `hd ask` moves to the background. Wait for that task's completion message, then handle its output in step 4. In interactive pi with `pi-bg-bash`, run `hd ask` in the foreground when you have no independent work; when you do, pass `background: true` without `hold: true`, handle its completion message right away if it arrives while you work, and end the turn only while the task is still running so the completion message wakes you (do not poll with `pgrep`/`pidwait`; in non-interactive `pi -p`, keep `hd ask` in the foreground because ending the turn exits and kills pending background tasks). Other clients: launch through your shell tool, retain its task handle, and use its completion notification or wait operation until the command finishes.

## Who does what

| work | who |
|---|---|
| recon: where things live, how a flow runs, call sites, the pattern to copy | scout |
| external research: vendor docs, APIs, pricing, limits, public specs | researcher |
| review of a diff: the defects it introduces, each with proof | reviewer |
| code from a brief: backend logic, refactors, tests, UI from a prototype | a fresh worker per brief |
| runs: tests, builds, stands, docker, databases, measurements, logs, CI logs, driving a TUI | sidekick `sk`: the first `hd ask sk` spawns it; it reports 3–5 numbers and a log path |
| decisions, briefs, diff review; a change shorter to write than to brief | you |

Complex logic goes to a worker when Traps and Acceptance cover its edge cases; you read that diff line by line.

## Loop

1. **Decide.** Recon goes to a scout in two steps. First take 1–3 quick orientation calls (`ls`, `git log`, `gh`, `AGENTS.md`) — or one `Depth: quick` map scout when the boundaries are unclear — to find the seams. Then fan out: one scout for a single cohesive area or flow, or parallel scouts (typically 2–4, one per independent area, subsystem, or issue) rather than packing unrelated topics into one brief. Past three searches (grep, find, ls) on one question, you are doing recon: hand it over. You read only the lines where a decision lives, starting from the scout's file:line, and settle every choice the task contains, down to names and mappings. Where the result lives and what it replaces is the user's call: one question before the first brief. Done when no open choice is left for the executor. Working from an issue: its facts are hypotheses until a scout confirms them at the current HEAD; a false fact or a choice that is the user's sends the issue back to the user with the question (with the `needs-info` label when the project uses the `issue-workflow` labels), never into the brief as your guess.
2. **Brief.** Read the `brief` skill ([../brief/SKILL.md](../brief/SKILL.md)) before your first brief of the session, and write the brief in its format to a file. When working from a `ready-for-agent` issue whose facts hold at HEAD, carry its brief sections (`Goal` through `Check`) directly into the worker brief instead of re-deriving them. Give one worker a cohesive subtask or vertical slice with its tests; do not micro-slice a subtask into single-file workers. Done when an agent with zero context could execute it without guessing.
3. **Ask and wait.** Before you spawn, tell the user in one line which agents start, on which model, and why. Launch `hd ask <name> @brief.md --timeout 600000` through your client's shell tool. Parallelism follows worktree boundaries: fan out scouts and reviewers in the same checkout, run at most one worker per worktree, and give parallel workers separate git worktrees (`git worktree add <dir> -b <branch>` or `herdr worktree create`, plus any repo bootstrap, then `hd spawn <name> worker --cwd <dir>`). For a parallel fan-out, wait on the group in one call (`hd wait <name1> <name2> ... --timeout 600000`) instead of separate background wakeups per agent. Continue only work that does not overlap any running agent's brief — never duplicate the recon, research, or edits you assigned them. When no independent work remains and the agent has not finished yet, wait on the existing task handle until the command returns, or end the turn only when your client stays alive and automatically wakes you on background task completion (as in Antigravity CLI or interactive pi with `pi-bg-bash`). A shell tool yielding control means the command is still running. `STATUS: still_working` comes every 10 minutes while the agent works: give the user one line on who is still running and what is done, then `hd wait <name> --timeout 600000` (or `hd wait <name1> <name2> ...`). Without automatic wake-up, do not end your turn while an agent you asked is running: nothing wakes you when it finishes. Keep short local checks (`git`, one targeted test) with you; route full repo verify/builds, Docker and e2e suites, local stands and DBs, and long logs to `hd ask sk`. Done when the command returns an envelope to handle in step 4.
4. **Read the envelope** by meaning; small models drift its keys and language.
   - `needs_decision`: decide, or ask the user if the choice is theirs, then `hd ask` the same agent; it keeps its context. A brief that contradicts the code is your error: fix the brief.
   - `failed`: send the same agent the concrete defect. After two failed corrections, do it yourself or re-brief a fresh worker.
   - `blocked_ui`: the agent shows a dialog. Ask the user before answering it. For Codex this includes the hook-review and folder-trust dialogs at startup; hd reports them before sending the brief.
   - `provider_error`: `hd` already retried once and went through the slot's `fallback`; the output names every model it tried. Check the working tree, then re-ask or re-brief. A 401 or 403 is a key or subscription: report the agent and model to the user, who picks the model.
   - `cancelled`: the turn was interrupted. Check the working tree before deciding whether to continue.
   - `tui_exited`: the executor closed before finishing. Inspect its diagnostics and diff, then use `hd resume` if the task should continue.
   - To investigate a concrete sign of a problem, `hd peek <name>`. Routine waiting uses the task handle.
   - `done`: verify.
5. **Verify.** Every claim in SUMMARY is **unverified** until you see its evidence. Done when:
   - writer: the `--- check` block under SUMMARY shows exit=0 and the expected output, `--- red` (when present) shows a non-zero exit, the `--- scope` block shows 0 outside Scope, and you read `hd diff <name>` (exactly what this ask changed) against the brief: every R has its hunk, every Acceptance case its passing test unchanged from the brief, every hunk in scope, every called API exists, every assumption is one you would make; read every new or changed test file in full, not a truncated prefix, and confirm each Acceptance `input → expected` literal assertion is present unchanged from the brief;
   - scout or reviewer: read the `OUTPUT_FILE`, confirm `--- claims` shows 0 not found and 0 found in repo, and open the `inferred:` claims your decision rests on;
   - researcher: read the `OUTPUT_FILE` before synthesizing an answer, and open the source for any decision-critical claim that is not direct with high confidence.
   Then record the **lesson**: for each `failed`, brief that contradicted the code, diff you rejected, or correction you sent, run `hd note <name> "<root cause in one line>"`.
6. **Stop.** `hd stop` one-shot agents once accepted. Use context size from `hd ls` to choose a fresh agent for the next brief. Let the current brief finish; if a context limit actually prevents progress, hand off the evidence and all unfinished requirements to a fresh agent. `hd resume <name>` brings a stopped agent back with its context, model, and cwd, for a follow-up on the same task.

`hd` appends one line per finished ask to `~/.cache/herdr-delegate/journal.jsonl`: status, check exit, Scope, changed and outside-Scope files, brief and payload paths. Your `hd note` lessons land there too; read the journal for recurring causes before changing how you brief.

The assigned brief remains the completion criterion while waiting. Elapsed time and other agents finishing are not reasons to shorten it or request an early report. Intervene on a concrete error, a request for a decision, observed work outside the brief, a stalled or ballooning context (e.g., `ctx` approaching or past 200k on `STATUS: still_working` — inspect with `hd peek`, then stop and hand off a narrower brief to a fresh agent if it is looping), or a user instruction. A timeout calls for checking `ctx`, `elapsed`, and progress before continuing the wait.

## Briefs in hd

The first `@file` or structured brief of a `worker` is checked before it is sent: all nine sections — `Goal:`, `Context:`, `Decisions:`, `Requirements:`, `Removes:`, `Traps:`, `Acceptance:`, `Scope:`, `Check:` — start their own line; `Removes:` and `Traps:` have content (`nothing` and `none — <reason>` when there is nothing to report); `Scope:` carries at least one backticked path; `Acceptance:` has a non-empty `Seam:` line and one `input → expected` line per distinct `R[0-9]+` in `Requirements:` (at least one); `Check:` runs a real verification command, not `true`, `:`, a standalone `git diff --check`, or `--listTests`. A rejection prints every violation and sends nothing; fix the brief per [../brief/SKILL.md](../brief/SKILL.md). Non-code errands go to a `scout` or `sidekick`. Follow-up asks are not checked.

Two fields of the brief are mechanical here. After the reply, `hd` runs Check in the agent's cwd (10 minute cap) and appends its exit code and output tail under `--- check`, and lists every changed file outside Scope under `--- scope`. Both apply to one ask: repeat them in every correction. The agent shows each Acceptance case red, then green, in SUMMARY. Check runs under pipefail: end it with the test command or pipe into `tail`, never `head`, whose early exit fails the pipe. `hd ask` refuses a worker while another ask is active in the same git worktree, and refuses any ask while a worker is active there, so Scope and red gates stay active; read-only roles run in parallel freely. When the agent reports done and Check fails or files changed outside Scope with no concurrent ask, hd sends the agent the failure, up to two rounds, and shows each round as a `--- autofix` line before the envelope.

For a scout or a reviewer, hd also checks the payload: each cited quote must be in the file within three lines of the cited line, and a `ref:path:line` citation (a commit, branch, or tag) is checked against that ref's git blob; each `ABSENT:` string must occur nowhere in the repository. Failures go back to the agent in the same autofix rounds and show under `--- claims`, with the autofix prompt capped at 20 entries and the rest reported as not shown. When at least 20 citations fail, half of them with `no such file`, and no ABSENT string was found, hd skips the claims autofix and prints `--- autofix skipped` instead of spending a round on a likely wrong ref, path prefix, or cwd. A file a scout or reviewer changes in the repository shows under `--- scope` even when its brief has no Scope. For a `reviewer`, `hd ask` also enforces the review cap mechanically: it refuses a second review by the same model at the same worktree/HEAD and refuses a third review round on the same worktree/branch unless `--force` is passed.

A scout brief lists its questions and may set `Depth: quick | normal | deep`; without it the scout works at `normal`. `quick` answers from the paths and names in the brief, `deep` follows every call site of the named symbols and reads their tests. The payload opens with `## Questions`: each question gets a cited answer, an `ABSENT:` line, or what stopped the scout.

For a worker whose Check passes, hd reverts the changed implementation files (not tests, not Markdown) to the ask's start, runs Check again and expects it to fail, then restores them; a pass goes back to the worker and shows under `--- red`. Add `Red: skip` to a brief whose change keeps behavior, such as a refactor.

## Roles

| role | lifetime | writes code | payload |
|---|---|---|---|
| `sidekick` | whole session; runs and measures, remembers the environment | small fixes | logs, measurements |
| `worker` | one brief; clean start or a parallel worktree | yes | R → file:line → test |
| `scout` | one brief: its questions at a set depth | no | required: code context with file:line |
| `reviewer` | one review | no | required: findings with file:line and a failure scenario, or `No findings.` |
| `researcher` | one question | no | required: sourced research brief |

Each `hd ask` hands the agent a fresh OUTPUT_FILE outside the repo for its payload. Code results live in the working tree, knowledge in the payload. Pass a payload to the next agent by path ("Read <path> first") so it bypasses your context.

## Review

The `pr-risk` skill sets the tier, the reviewer count and every merge gate; read it before reviewing a branch. Here its reviewers run the `reviewer` role ([roles/reviewer.md](roles/reviewer.md)) from config slots that carry the models the project's Workflow section names, all on one brief filled from [../pr-risk/references/review-brief.md](../pr-risk/references/review-brief.md):

```
hd spawn rv-a review-a                  # slots with "role": "reviewer"
hd spawn rv-b review-b                  # High only: a second model family
hd ask rv-a @brief.md                   # launch both, or wait together with:
hd ask rv-b @brief.md                   # hd wait rv-a rv-b --timeout 600000
```

Medium runs one reviewer. High runs two from different model families in parallel, plus a third strong reviewer only from a distinct model family when the change spans several services (never duplicating an existing reviewer's family). Different models find different defects. Merge their findings as `pr-risk` describes; fixes then go through the Loop.

## Experimental add-ons

Two extensions of this skill live beside it, off by default and outside the review policy. Neither changes what the policy requires.

- [experimental/ui.md](experimental/ui.md): an approved prototype as the spec for looks only, accepted by a computed-style diff (`experimental/style-diff.mjs`, Playwright from the project) or by `tmux` screen text for TUIs.
- [experimental/skeptic.md](experimental/skeptic.md): an independent reviewer from another model family attacks an accepted diff against the spec, never seeing your brief.

## Limits

These are documented limits, not security boundaries. Hand a brief to an agent only when you would run its Check yourself.

- **Read-only roles are an instruction, not a sandbox.** A scout or reviewer has `write` so it can produce its payload, and a Codex scout or reviewer runs with `-s workspace-write`. A Codex worker runs with `-s danger-full-access`, because the workspace-write sandbox blocks the network and the build caches outside the repo that its tests need. A misbehaving scout or reviewer can change the working tree; `hd diff` and `git status` are how you find out.
- **Agents belong to the pane that spawned them.** `hd` refuses to run when the pane in `HERDR_PANE_ID` is not an ancestor of the calling process, so one lead cannot drive another lead's agents by setting its environment. A lead restarted in a new pane does not pick up the old pane's agents.
- **Scope is checked after the turn.** `hd` snapshots the tree before the ask and lists changed files outside Scope after it. Nothing stops the write while it happens. `hd` blocks concurrent asks involving a worker in the same git worktree; external edits outside `hd` (a lead's edits or merges) still land in diff/Scope, and parallel read-only asks in the same tree appear under `--- concurrent`, so their changes land in this ask's lists. Give parallel writers their own worktrees.
- **Check is an arbitrary shell command.** It comes from the brief and runs in the agent's cwd with a 10 minute cap. Treat a brief as code, because `hd` runs part of it.
- **The journal is local.** `~/.cache/herdr-delegate/` holds payloads, briefs and journal lines in plain text; nothing prunes it.

## Requirements

`bash` 4.4+, `jq`, `git` 2.31+, and `timeout` or `gtimeout` from GNU coreutils; on macOS, `brew install bash coreutils jq`. Herdr, with the lead running inside a pane (`HERDR_ENV=1`), and any Herdr integration its executor needs. An executor on `PATH`: pi (every role), Codex (scouts, reviewers and workers), or ZCode (every role after [its one-time setup](executors/zcode.md)). Linux and macOS; on Windows, run it in WSL. CI runs the test suite on both systems; live runs with real Herdr panes have been on Linux.

The harness, model and thinking come from the [config file](#configuration); `PI_CODING_AGENT_DIR` points at pi's agent directory. For ZCode, the model is `providerId/modelId`, thinking needs model support, and provider keys stay in its personal config; [executors/zcode.md](executors/zcode.md) has its private profile and limits. Per agent: `hd spawn <name> <slot> --agent codex --model M --thinking T --cwd DIR`.

## Configuration

`hd spawn <name> <slot>` takes the harness, model and thinking from a slot in `${XDG_CONFIG_HOME:-$HOME/.config}/hd/config.json`, or the file `HD_CONFIG` names:

```json
{
  "default": {"harness": "zcode", "model": "provA/model-a", "thinking": "max",
              "fallback": [{"harness": "pi", "model": "provB/model-a"}]},
  "slots": {
    "researcher": {"harness": "pi", "model": "provB/model-a",
                   "pi_extensions": ["~/path/to/pi-web-access/index.ts"]},
    "review-b": {"role": "reviewer", "harness": "codex", "model": "<model>"}
  },
  "providers": {"provA": {"pi_extension": "~/path/to/provA-extension.ts"}}
}
```

- A slot holds `role`, `harness`, `model`, `thinking`, `pi_extensions` and `fallback`; a field the slot leaves out comes from `default`. `role` defaults to the slot's name, so the slots `sidekick`, `worker`, `scout`, `reviewer` and `researcher` exist without an entry.
- `model` is written the harness's way: pi's exact ID from `pi --list-models`, Codex's model name, ZCode's `providerId/modelId`. Codex reads `thinking` as its reasoning effort, with `max` sent as `xhigh`.
- `pi_extensions` load into every pi agent of the slot; `providers.<id>.pi_extension` loads when a pi model of the slot, or of its fallback, belongs to provider `<id>`. A researcher on pi needs a web-search extension here.
- `fallback` lists replacements, each overriding `harness`, `model` or `thinking`. When a provider error survives the one retry, `hd` closes the agent's pane, starts the same name on the next replacement with a fresh session, sends the brief again, and prints `--- fallback: <model> → <model>: <error>`. The agent stays on the replacement; a new spawn starts from the slot's own model.
- `--agent`, `--model` and `--thinking` override the slot for that one agent.
- `hd spawn` refuses, before it creates a pane, when the file is missing or not JSON, when the slot resolves no model, an unknown harness, a role its harness does not run, or a pi ID that is not exact, and while the environment still sets one of the `HD_*` variables that carried harness, model, thinking or pi extensions before the config file.

## Tests

```
bash skills/herdr-delegate/tests/run.sh
```

The suite runs `hd` against a fake `herdr` in `tests/fake/`, with its own cache dir and git repository per case. It needs no Herdr, no model, and no network.
