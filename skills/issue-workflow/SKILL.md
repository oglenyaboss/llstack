---
name: issue-workflow
description: Use when capturing, triaging, or executing GitHub issues. Capture is not readiness; this skill holds the readiness gate and the execution guardrail.
---

# Issue workflow

One rule carries the rest: **capture is not readiness**. An issue that exists is a claim someone wrote down, not permission to execute it.

Readiness means four things are true at the base commit:

1. every factual claim in the body checks out against the code at that commit,
2. acceptance cases are written as observable outcomes,
3. the owner decision is recorded in the owner's words, or the issue needs no decision,
4. expected risk is estimated from `.github/risk-tiers.yml`.

Execution is separate from all four. The repo's permissions and the review policy decide whether a change may be pushed or merged.

## Project values

Read the `Workflow` section of the project's agent instructions (CLAUDE.md or AGENTS.md) before acting: decision owner, base branch, label names, check command, and the GitHub Project when there is one.

Without that section, the owner is the user you are working for, the base is `origin/HEAD`, and the labels carry the role names below. The six role names are canonical; a repo may map them to its own label strings in the Workflow section, and then you apply the mapped string. A missing value you need is a question to the owner, never a guess.

## Roles

| Role | Asserts | Does not assert |
|---|---|---|
| `needs-triage` | Someone captured it. | That any factual claim is true. |
| `needs-info` | It is blocked on a decision, or a stated fact failed a check. | That the rest of the body is right. |
| `ready-for-agent` | The four readiness conditions hold at the recorded commit. | Permission to push, merge, or deploy. |
| `ready-for-human` | The same, plus a recorded reason an agent cannot do it. | That a human has started. |
| `wontfix` | Closed, with the reason in a comment. | That the work is impossible later. |

One state role at a time. `rework` is a marker, not a state: it flags an issue or PR that was redone, reverted, or hotfixed after merge.

## The path

### 1. Capture

Thirty seconds. Write what was seen, where, and the reporter's words, without interpretation. Apply `needs-triage` when no decision is needed. Apply `needs-info` and add a question when a decision is needed.

Do not write acceptance cases at capture. Do not write a decision the owner has not given.

Template: [templates/issue-capture.md](templates/issue-capture.md). Done when the body names the observation, the location, and the reporter's words, and a decision ticket carries the question with options and a recommendation.

### 2. Triage

Work the `needs-triage` queue in one pass. For each issue, decide whether a decision is required. The conditions are in [references/readiness.md](references/readiness.md). A decision ticket moves to `needs-info` with the question. The rest stay in triage until the readiness pass.

Done when every captured issue has exactly one state role, and every `needs-info` issue has a question someone can answer.

### 3. Readiness

Fetch the base branch, pin the commit, and check every factual claim against that commit. Record the citation and the SHA. Fill the brief-aligned sections (`Goal`, `Context`, `Decisions`, `Requirements`, `Removes`, `Traps`, `Acceptance` with `Seam:` and `input → expected`, `Scope`, `Check`) per [templates/issue-ready.md](templates/issue-ready.md) and `skills/brief/SKILL.md`. Copy the owner's answer verbatim into `Decisions`. Set the expected risk and the size.

Procedure: [references/readiness.md](references/readiness.md). Done when every claim has a `path:line` citation at the recorded SHA, the brief sections are complete (`Traps` and literal runtime `Acceptance` cases included), and the owner decision is either filled verbatim or marked as not required.

A fact that fails, or a choice that belongs to the owner, sends the issue to `needs-info` with the question in a comment. Do not write a guess into the body.

### 4. Execution

The first action after claiming an issue is to re-check its facts at the current base. A fact that no longer holds, or a decision the body does not contain, sends the issue back to `needs-info` and you move to the next issue. Do not improvise around a contradiction.

Batch selection, the PR shape, and the merge gate: [references/execution-loop.md](references/execution-loop.md) and [references/dependencies-and-frontier.md](references/dependencies-and-frontier.md).

### 5. Completion

Four different claims get confused in most trackers:

| Claim | What it proves | Evidence |
|---|---|---|
| Worker reports done | The code was written and the local check passed | Check exit code, scope block, a diff that was read |
| PR merged | The gate for its risk tier passed | CI result, review record, merge commit |
| Deployed | The artifact runs somewhere | Deploy record and, for high risk, the first-hour watch |
| Owner accepted | The behavior is right in the place the owner uses it | A comment from the decision owner with what they checked |

Only the last one closes the issue by default. A merged PR references the issue with `Refs #N` and leaves it open. `Closes #N` is reserved for the case where the Workflow section records auto-close on merge as a deliberate deviation; even then, record acceptance in a comment, because a closed issue is not an accepted one.

Do not report "done" for work that reached the merge stage. Say which of the four it reached.

### 6. Rework

Apply `rework` to the issue or PR that had to be redone, reverted, or hotfixed after merge. Once per cycle, take each `rework` item and answer one question: which layer should have caught it? Capture, readiness, the execution guardrail, review, or a decision nobody recorded.

Fix the source, not the symptom: a test, a lint rule, a review brief question, a line in the project's agent instructions, or an ADR. A finding caught twice becomes a check. If the same class keeps arriving, the process is leaking at that layer, and another reminder will not fix it.

## Sizes and the plan

Size measures human attention to review, integrate, and accept, not code volume and not elapsed time. Record `xs`, `s`, or `m` as a label when the repo has size labels, otherwise as a line in the body. Split anything larger than `m` before taking it. Details: [references/estimation.md](references/estimation.md).

## The board

When the Workflow section names a GitHub Project, the board is a planning view over a subset of issues. Board status is not a readiness label, and a card in a Done column is not owner acceptance. Commands and quirks live in the `github-projects-api` skill. When it names none, ignore the board entirely; issues are the record.

## Review policy

Risk tiers, reviewers, evidence, and merge gates are owned by the `pr-risk` skill and its review policy; the Workflow section binds them to local commands and owners. This skill estimates a tier and never restates the gate. When an estimate and a gate disagree, the policy decides.

## Sources

What came from Matt Pocock's triage roles and what came from the author's process, with the changes: [references/sources.md](references/sources.md).
