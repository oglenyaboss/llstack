# Dependencies and the frontier

The frontier is the set of ready issues that nothing blocks. It is the only honest answer to "what can be started now".

## Native dependencies first

GitHub issue dependencies are the record. They show in the UI, they survive edits to the body, and they are what the frontier query reads.

Add an edge with the blocker's database id, not its number and not its node id:

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
BLOCKER_DB_ID=$(gh api "repos/$OWNER_REPO/issues/$BLOCKER" --jq .id)
gh api --method POST "repos/$OWNER_REPO/issues/$BLOCKED/dependencies/blocked_by" -F issue_id="$BLOCKER_DB_ID"
```

A body line such as `Blocked by: #12` is the fallback for a tracker where dependencies are unavailable. It is not the default, because nothing enforces it and the issue still looks startable.

Read the blocker's state as well as the edge. GitHub reports `issue_dependencies_summary.blocked_by`, which counts open blockers only:

```bash
gh api "repos/$OWNER_REPO/issues/$N" --jq '.issue_dependencies_summary.blocked_by'
```

Zero means unblocked. A blocked issue whose blocker closed is unblocked, with no edit needed.

## Frontier query

Read only, no writes:

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
READY=ready-for-agent   # or the label the Workflow section maps this role to

OUT="${TMPDIR:-/tmp}/llstack-ready.json"
gh issue list --state open --label "$READY" --limit 100 \
  --json number,title,labels,assignees,updatedAt > "$OUT"

python3 - "$OWNER_REPO" "$OUT" <<'PY'
import json, subprocess, sys
repo, path = sys.argv[1], sys.argv[2]
issues = json.load(open(path))
for issue in issues:
    if issue["assignees"]:
        continue
    n = issue["number"]
    blocked = subprocess.run(
        ["gh", "api", f"repos/{repo}/issues/{n}", "--jq", ".issue_dependencies_summary.blocked_by"],
        capture_output=True, text=True,
    ).stdout.strip() or "0"
    if blocked != "0":
        continue
    print(n, issue["title"])
PY
```

Order the result by the repo's priority labels, then by `updatedAt`. The first unblocked issue in that order is the next candidate.

The loop above makes one API call per ready issue. For a large queue, fetch `issue_dependencies_summary` by paging GraphQL instead. Do not guess the blocked state from the body text.

## Claiming

Assign yourself before writing code:

```bash
gh issue edit "$N" --add-assignee @me
```

That edit is the first write of the session. Release it with `--remove-assignee @me` when you stop without a PR.

## Containers

A large effort is a parent issue with sub-issues. The parent is a container, not a work item: it carries no readiness label and never appears in the frontier. Decompose it into child issues of size `s` or `m`, then work the children through the normal path.

```bash
gh issue create --title "..." --body-file body.md --parent "$PARENT"
```

Where sub-issues are unavailable, add the children to a task list in the parent body and put `Part of #N` at the top of each child.

## Batching

The frontier gives you candidates. Batching turns them into PRs:

- same area, same flow, same files;
- three or four issues, tunable per team;
- one PR, one commit per issue;
- high risk alone;
- a decision issue alone.

When two ready issues conflict, one of them is not ready. Do not resolve the conflict inside a batch; send the pair back to triage with the question.

## Failure modes

- Using the issue number as `issue_id`: the mutation fails or links the wrong issue. Use the database id from `gh api ... --jq .id`.
- Reading only the edge and not the blocker's state: a closed blocker still looks like a block and the issue never starts.
- Duplicating blockers in the body and in the dependencies graph: the graph wins and the body line goes stale.
- Claiming a whole parent issue: nobody can tell which child is in progress.
- Treating a blocked issue as not ready: it may be perfectly ready and simply not startable. Readiness is about facts, not scheduling.
