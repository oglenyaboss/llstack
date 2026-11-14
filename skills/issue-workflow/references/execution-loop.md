# Execution loop

Working an issue from `ready-for-agent` to accepted. The loop is daily; the gates inside it are fixed.

## The loop

### 1. Pick from the frontier

List what is ready and unblocked, with no open blocker and no assignee. Query in [dependencies-and-frontier.md](dependencies-and-frontier.md).

Order by the repo's priority labels, then by age. Do not start with whatever is loudest in a chat.

### 2. Re-check the facts

Open the issue and check its claims at the current base commit, not the commit recorded at readiness. Base moves; a fact checked last week may be false now.

- All facts hold: continue.
- A fact fails and the ask is unchanged: correct the body with a comment and continue.
- A fact fails and changes the work, or the body needs a choice it does not contain: comment with the question, set `needs-info`, next issue.

Improvising here is how a batch of small changes becomes one surprising PR.

### 3. Assemble a batch

A batch is a set of issues in one area that one PR can carry.

- Three or four issues by default. The number is a team setting, not a law.
- One PR per batch, one commit per issue. The commit message names the issue number.
- High risk always travels alone, in its own PR. Never mix a high-risk change with anything else.
- A decision ticket never rides in a batch. It gets its own PR so the accepted behavior is reviewable alone.
- Issues that touch the same files or the same flow belong together. Issues in different services do not.

Claim each issue with an assignee before starting. Release the claim if you stop.

### 4. Implement and check

Run the repo's `check` command before every push. The review policy decides what evidence the PR needs beyond that: test output, a screenshot, rollback instructions, a local e2e of the affected flow.

A UI screenshot is evidence for a UI change. When a backend-only change touches a path the policy expects a screenshot for, the human owner may approve an explicit N/A in the PR. It is an approval, not a silent omission, and it is recorded.

### 5. Open the PR

- Title names the outcome, not the file.
- Body carries: what changed, the risk tier and the paths that set it, the evidence the policy asks for, the issues it touches, and a rollback line for high risk.
- Link issues with `Refs #N`. Use `Closes #N` only when the Workflow section records auto-close on merge as a deliberate choice.
- Keep one review round. On high risk, fixes get a second review of the fix diff, by one reviewer. New commits after an approval need a new approval; an approval covers the commit it was given on.

### 6. Pass the gate

The gate depends on the risk tier and is defined in the `pr-risk` skill, `skills/pr-risk/references/review-policy.md`. This skill does not restate it.

If the diff's tier is above the expected tier from the issue, stop before review and say so. A jump in tier usually means the change drifted outside its scope.

Never lower a tier to pass a gate. Raise it and take the slower path.

### 7. Deploy and watch

A merge is not a deploy. After the deploy, high-risk changes get the first-hour watch named in the Workflow section: errors, failed deliveries, queue depth, whatever that command checks, plus rollback instructions ready.

### 8. Record acceptance

The decision owner checks the behavior where they use it and comments with what they checked. That comment is the acceptance record.

- No issue closes before this, by default.
- If the repo enabled auto-close on merge, the issue closes early. Record acceptance anyway, and treat an acceptance that never arrives as an open question, not as done.
- When acceptance finds a defect, apply `rework`, reopen or file a follow-up, and run the rework pass.

### 9. Keep one batch in review

While a batch is in review, do not start the next one. Two batches in review means two sets of evidence to hold in mind and two diffs to reconcile when the first one changes.

## The completion ladder

Four claims, four kinds of evidence. Report which one you reached.

| Stage | Evidence | What it is not |
|---|---|---|
| Worker done | `check` exit 0, scope clean, diff read line by line | Accepted |
| Merged | Gate passed, merge commit on the base branch | Deployed |
| Deployed | Deploy record, first-hour watch for high risk | Accepted |
| Accepted | The decision owner's comment naming what was checked | Permanent; a later defect reopens it |

Statements like "shipped", "finished", or "done" need a stage attached. A merged PR reported as done is the most common way a process loses track of what is actually live.

## After the cycle

Count three things: issues closed, time from claim to acceptance, and the share of closed issues carrying `rework`. Compare them with what was committed at the start of the cycle. If `rework` is growing, find the layer that should have caught the rework and fix it there. The per-item pass lives in the main skill, step 6.

## Estimates in the loop

The size on the issue is human attention, not machine time. It tells you how many issues fit in a cycle, not how long a model takes to type. See [estimation.md](estimation.md).
