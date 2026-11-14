---
name: herdr-delegate
description: "Lead mode in Herdr: agents in panes execute while you decide, brief, and verify. Use when asked to delegate, act as the lead, or name a sidekick, worker, scout, or researcher."
---

# Herdr delegate

You are the **lead**: you decide, brief, and verify; agents in Herdr panes execute, usually on a cheaper model than yours (harness and model come from `HD_HARNESS`, `HD_MODEL`, `HD_THINKING`; `--agent`, `--model`, `--thinking` override per agent). They copy well, invent badly, and follow the brief literally, never questioning it. So the result is only as good as the brief, and an error in the brief passes your verification, because you verify against that same brief. Logs, test output, and payloads stay in files; you read the lines you decide on.

Driver: `hd` in this skill's directory; the commands below call it `hd`. Run it bare for usage.

Codex leads: read [clients/codex.md](clients/codex.md) before the first `hd ask` for the launch and wait recipe. Other clients: launch through your shell tool, retain its task handle, and use its completion notification or wait operation until the command finishes.

## Who does what

| work | who |
|---|---|
| recon: where things live, how a flow runs, call sites, the pattern to copy | scout |
| code from a brief: backend logic, refactors, tests, UI from a prototype | a fresh worker per brief |
| runs: tests, builds, stands, docker, databases, measurements, logs, CI logs, driving a TUI | sidekick `sk`: the first `hd ask sk` spawns it; it reports 3–5 numbers and a log path |
| decisions, briefs, diff review; a change shorter to write than to brief | you |

Complex logic goes to a worker when Traps and Acceptance cover its edge cases; you read that diff line by line.

## Loop

1. **Decide.** Recon goes to a scout. Past three searches (grep, find, ls) on one question, you are doing recon: hand it over. You read only the lines where a decision lives, starting from the scout's file:line, and settle every choice the task contains, down to names and mappings. Where the result lives and what it replaces is the user's call: one question before the first brief. Done when no open choice is left for the executor. Working from an issue: its facts are hypotheses until a scout confirms them at the current HEAD; a false fact or a choice that is the user's sends the issue back to the user with the question (with the `needs-info` label when the project uses the `issue-workflow` labels), never into the brief as your guess.
2. **Brief.** Read the `brief` skill ([../brief/SKILL.md](../brief/SKILL.md)) before your first brief of the session, and write the brief in its format to a file. Done when an agent with zero context could execute it without guessing.
3. **Ask and wait.** Launch `hd ask <name> @brief.md` through your client's shell tool; the default timeout is 50 minutes. Continue independent work while it runs. When none remains, wait on the existing task handle until the command returns. A shell tool yielding control means the command is still running. `STATUS: still_working` from `hd` means continue with `hd wait <name>`. Done when the command returns an envelope to handle in step 4.
4. **Read the envelope** by meaning; small models drift its keys and language.
   - `needs_decision`: decide, or ask the user if the choice is theirs, then `hd ask` the same agent; it keeps its context. A brief that contradicts the code is your error: fix the brief.
   - `failed`: send the same agent the concrete defect. After two failed corrections, do it yourself or re-brief a fresh worker.
   - `blocked_ui`: the agent shows a dialog. Ask the user before answering it.
   - `provider_error`: `hd` already retried once. Check the working tree, then re-ask or re-brief.
   - To investigate a concrete sign of a problem, `hd peek <name>`. Routine waiting uses the task handle.
   - `done`: verify.
5. **Verify.** Every claim in SUMMARY is **unverified** until you see its evidence. Done when:
   - writer: the `--- check` block under SUMMARY shows exit=0 and the expected output, the `--- scope` block shows 0 outside Scope, and you read `hd diff <name>` (exactly what this ask changed) against the brief: every R has its hunk, every Acceptance case its passing test unchanged from the brief, every hunk in scope, every called API exists, every assumption is one you would make;
   - scout: 1–2 key file:line citations open to what the payload says; one mismatch makes the whole payload suspect;
   - researcher: each decision-critical claim is direct with high confidence, or you opened its source.
   Then record the **lesson**: for each `failed`, brief that contradicted the code, diff you rejected, or correction you sent, run `hd note <name> "<root cause in one line>"`.
6. **Stop.** `hd stop` one-shot agents once accepted. Use context size from `hd ls` to choose a fresh agent for the next brief. Let the current brief finish; if a context limit actually prevents progress, hand off the evidence and all unfinished requirements to a fresh agent. `hd resume <name>` brings a stopped agent back with its context, model, and cwd, for a follow-up on the same task.

`hd` appends one line per finished ask to `~/.cache/herdr-delegate/journal.jsonl`: status, check exit, Scope, changed and outside-Scope files, brief and payload paths. Your `hd note` lessons land there too; read the journal for recurring causes before changing how you brief.

The assigned brief remains the completion criterion while waiting. Elapsed time, growing context, and other agents finishing are not reasons to shorten it or request an early report. Intervene on a concrete error, a request for a decision, observed work outside the brief, or a user instruction. A timeout calls for checking state and continuing the wait while the agent is progressing.

## Briefs in hd

Two fields of the brief are mechanical here. After the reply, `hd` runs Check in the agent's cwd (10 minute cap) and appends its exit code and output tail under `--- check`, and lists every changed file outside Scope under `--- scope`. Both apply to one ask: repeat them in every correction. The agent shows each Acceptance case red, then green, in SUMMARY.

## Roles

| role | lifetime | writes code | payload |
|---|---|---|---|
| `sidekick` | whole session; runs and measures, remembers the environment | small fixes | logs, measurements |
| `worker` | one brief; clean start or a parallel worktree | yes | R → file:line → test |
| `scout` | one question | no | required: code context with file:line |
| `researcher` | one question | no | required: sourced research brief |

Each `hd ask` hands the agent a fresh OUTPUT_FILE outside the repo for its payload. Code results live in the working tree, knowledge in the payload. Pass a payload to the next agent by path ("Read <path> first") so it bypasses your context.

## Review

The `pr-risk` skill sets the tier, the reviewer count and every merge gate; read it before reviewing a branch. Here its reviewers are scouts on the models the project's Workflow section names, all on one brief filled from [../pr-risk/references/review-brief.md](../pr-risk/references/review-brief.md):

```
hd spawn rv-a scout --model <model A>
hd spawn rv-b scout --model <model B>   # High only: a second model family
hd ask rv-a @brief.md                   # launch both through the client's shell tool
hd ask rv-b @brief.md
```

Medium runs one scout. High runs two from different model families in parallel, plus the strong reviewer as a third scout when the change spans several services. Different models find different defects. Merge their findings as `pr-risk` describes; fixes then go through the Loop.

## Experimental add-ons

Two extensions of this skill live beside it, off by default and outside the review policy. Neither changes what the policy requires.

- [experimental/ui.md](experimental/ui.md): an approved prototype as the spec for looks only, accepted by a computed-style diff (`experimental/style-diff.mjs`, Playwright from the project) or by `tmux` screen text for TUIs.
- [experimental/skeptic.md](experimental/skeptic.md): an independent reviewer from another model family attacks an accepted diff against the spec, never seeing your brief.

## Limits

These are documented limits, not security boundaries. Hand a brief to an agent only when you would run its Check yourself.

- **Read-only roles are an instruction, not a sandbox.** A scout has `write` so it can produce its payload, and a Codex scout runs with `-s workspace-write`. A misbehaving scout can change the working tree; `hd diff` and `git status` are how you find out.
- **Scope is checked after the turn.** `hd` snapshots the tree before the ask and lists changed files outside Scope after it. Nothing stops the write while it happens.
- **Check is an arbitrary shell command.** It comes from the brief and runs in the agent's cwd with a 10 minute cap. Treat a brief as code, because `hd` runs part of it.
- **The journal is local.** `~/.cache/herdr-delegate/` holds payloads, briefs and journal lines in plain text; nothing prunes it.

## Requirements

`bash` 4.4+, `jq`, `git` 2.31+, and `timeout` or `gtimeout` from GNU coreutils; on macOS, `brew install bash coreutils jq`. Herdr, with the lead running inside a pane (`HERDR_ENV=1`), and the Herdr integration installed for the executor you use. An executor on `PATH`: pi for every role, Codex for scouts. Linux and macOS; on Windows, run it in WSL. CI runs the test suite on both systems; live runs with real Herdr panes have been on Linux.

Configuration is environment only, and all of it is optional: `HD_HARNESS` (`pi` or `codex`), `HD_MODEL`, `HD_THINKING`, `HD_PI_EXTENSIONS` (colon-separated), `PI_CODING_AGENT_DIR`. Per agent: `hd spawn <name> <role> --agent codex --model M --thinking T --cwd DIR`.

## Tests

```
bash skills/herdr-delegate/tests/run.sh
```

The suite runs `hd` against a fake `herdr` in `tests/fake/`, with its own cache dir and git repository per case. It needs no Herdr, no model, and no network.
