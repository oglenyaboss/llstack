# Capture and readiness

Two steps, deliberately separate. Capture records what someone saw. Readiness establishes what is true.

## Capture

Fast, on the way past the problem. The body holds the observation, the location, and the reporter's words. Nothing else.

A claim written at capture is a hypothesis. It has not been checked, and the readiness pass may delete it.

### When a decision is required

A decision ticket exists when any one of these holds:

- The change has more than one reasonable behavior the user would see: what appears, what hides, what a message says, which default wins.
- It touches an invariant or a gate the project treats as fixed.
- It reverses or contradicts behavior someone chose on purpose.
- The scope is the question: whether to do it at all, or how far to take it.
- The correct fix cannot be derived from the code and the issue.

Everything else is a batch ticket: a regression against described behavior, a crash, a layout defect, a flake, a CI or dependency fix, a mismatch between code and a written contract.

A batch ticket still needs readiness. It just does not need an owner decision.

### Which label

- No decision needed: `needs-triage`.
- Decision needed: `needs-info`, with the question in the body.

`ready-for-agent` is never applied at capture.

## Readiness

Four conditions. All four, at one commit.

### 1. Pin the commit

```bash
git fetch --prune origin
BASE=origin/HEAD   # or the base branch from the Workflow section
BASE_SHA=$(git rev-parse --short "$BASE")
```

Record `BASE_SHA` in the issue body. Every fact below is checked at that SHA, and a reader can tell how stale the check is. When the base moves during execution, re-check only the facts the diff touches, and record the new SHA.

### 2. Verify every factual claim

Work through the body sentence by sentence. A fact is a claim about the code: current behavior, where something lives, what a config value is, whether a test exists, who calls what.

For each one:

```bash
git show "$BASE_SHA:path/to/file" | sed -n '40,60p'
```

Write the result as `path:line` plus the SHA. A claim with no citation is not verified, and a claim checked against the working tree instead of the SHA is not verified either, because the tree may hold uncommitted edits.

If a claim fails:

- It was the reporter's hypothesis and the ask still stands: correct the body, say what is actually true, and continue.
- It changes what should be done, or the code already implements the request: comment with the finding and set `needs-info`, so the owner decides whether the issue still exists.

### 3. Brief-aligned spec (`Goal` through `Check`)

A `ready-for-agent` issue uses the same nine sections as an executable worker brief (`skills/brief/SKILL.md` is the single source of truth for their rules): `Goal`, `Context` (with the pinned SHA, patterns to copy, and conflicting tests), `Decisions`, `Requirements` (`R1..Rn`), `Removes`, `Traps`, `Acceptance` (`Seam:` plus one concrete `input → expected` line per `R`, exercised at runtime), `Scope`, and `Check`.

Capture design decisions, traps, and literal acceptance cases here at planning time so execution does not re-invent them. Use `nothing` for `Removes` and `none — <reason>` for `Traps` when nothing applies. Mechanical enforcement of the brief sections stays in `hd` at execution time, not in the issue tracker.

Not acceptance cases: "refactor the module", "make it robust", "add tests". Those are means, not outcomes.

Template: [../templates/issue-ready.md](../templates/issue-ready.md).

### 4. Owner decision

Only for a decision ticket. Copy the owner's answer verbatim into the decision section. Paraphrase is how a decision gets lost. When the decision constrains future behavior, record an ADR next to it and link the path.

An issue with a decision section that says "probably X" or holds the agent's recommendation is not ready. Set `needs-info` and ask.

### Risk and size

Estimate the risk tier by matching the paths the change will touch against `.github/risk-tiers.yml`: a path matching `high` is high, a path matching only `low` is low, anything else is medium, and the change takes the highest tier among its paths. Record the tier and the paths that produced it.

The estimate at readiness is the expected tier. The diff decides the actual tier at PR time, and the review policy decides whether the escalation blocks the merge. An agent may raise a tier. Lowering one belongs to the policy, not to the issue author.

Size goes in as `xs`, `s`, or `m`. Anything larger is split before it is marked ready.

### Apply

Set `ready-for-agent` only when all four conditions hold:

- the SHA is recorded and every fact cites it;
- the nine brief sections from [../templates/issue-ready.md](../templates/issue-ready.md) are filled (`Seam`, `Traps`, `Removes`, literal `Acceptance` cases, `Scope`, `Check`);
- the decision is verbatim, or marked not required;
- risk and size are set.

A decision ticket moves to `ready-for-agent` only after the owner's words are in the body. An agent's recommendation, however good, is not a decision.

## The mapping

Each role is the label of the same name, unless the Workflow section maps it to another string:

| Role | Applied when |
|---|---|
| `needs-triage` | Captured, not evaluated |
| `needs-info` | Waiting on a decision, or a fact failed |
| `ready-for-agent` | All four conditions hold |
| `ready-for-human` | Same, plus a reason an agent cannot do it |
| `wontfix` | Closed with a reason |
| `rework` | Redone, reverted, or hotfixed after merge |

When a role's label does not exist in the tracker, report it and stop. Do not invent a label string, and do not fall back to a similar one.

## Pull requests as requests

Off by default. If the Workflow section turns it on, external PRs use the same roles, with `gh pr` in place of `gh issue`. Internal PRs from the repo's own branches are not triage items.

## Permission

Readiness is not authorization. A `ready-for-agent` label does not grant a push to a protected branch, a merge, a deploy, or access to production data. Those come from the repo's permissions and the review policy, and nothing in the issue body changes them.
