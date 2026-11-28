Goal: an independent code review of branch <BRANCH> against <BASE>, as a ranked list of verified defects with file:line.

Context (read first):
- Diff under review: `git diff <BASE>...HEAD`; `git log --oneline <BASE>..HEAD` for the commit story. <Generated files, fixtures, prototypes: name them here as "skim, do not review line by line".>
- Risk tier: <low/medium/high from the project's classifier, with the files that set it, or "none">. On high, spend the depth on those files first.
- Spec / plan / prototype / issue: <paths or issue numbers, or "none">. The issue's decisions and acceptance criteria are the spec for A5.
- Batch: <a table `issue → commit sha → acceptance criteria`, or "none">. For a batch, A5 runs per commit (`git show <sha>` against its issue), then check seams between commits in the whole diff (A1).
- Recurring findings: <the project's list, e.g. docs/agents/recurring-findings.md, or "none">. Check every changed file against each.
- Project rules / contracts: <CLAUDE.md / AGENTS.md sections and contracts doc path, or "none">.
- Focus areas: <dirs or risky paths that carry the change>.

Review axes (A1–A6), impact check across usages outside the diff, evidence format, and payload shape live in [../../herdr-delegate/roles/reviewer.md](../../herdr-delegate/roles/reviewer.md) (`hd` reviewers receive it automatically; pass it alongside this brief for standalone subagents or other CLIs).
Done when: OUTPUT_FILE ranks verified findings high → low (or `No findings.`), lists checked areas and impact checked; SUMMARY gives counts per severity and the top 3 one-liners.
