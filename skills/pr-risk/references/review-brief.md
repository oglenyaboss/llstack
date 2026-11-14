Goal: an independent code review of branch <BRANCH> against <BASE>, as a ranked list of verified defects with file:line.

Context (read first):
- Diff under review: `git diff <BASE>...HEAD`; `git log --oneline <BASE>..HEAD` for the commit story. <Generated files, fixtures, prototypes: name them here as "skim, do not review line by line".>
- Risk tier: <low/medium/high from the project's classifier, with the files that set it, or "none">. On high, spend the depth on those files first.
- Spec / plan / prototype / issue: <paths or issue numbers, or "none">. The issue's decisions and acceptance criteria are the spec for A5.
- Recurring findings: <the project's list, e.g. docs/agents/recurring-findings.md, or "none">. Check every changed file against each.
- Project rules: <CLAUDE.md / AGENTS.md sections that define invariants and merge blockers>. Contracts doc: <path, or "none">.
- Main code areas: <dirs that carry the change>.

Review axes, in priority order:
A1. Correctness bugs: wrong logic, unhandled first/last/empty cases, races, stale cache/query keys, wrong mapping between backend DTO and UI.
A2. Contract and doc drift: producer ↔ schema ↔ contracts doc, checked in both directions (field in code but not in docs, and vice versa; types/optionality differ); any `*.md` that describes the changed code (find it with `rg` by changed symbol names and paths) and no longer matches it.
A3. Layer and module boundaries the project declares (e.g. FSD slices, public API via index.ts).
A4. Project invariants from the rules above: swallowed errors, leaked secrets, the project's named antipatterns.
A5. Spec conformance: a requirement of the spec missing or implemented differently.
A6. Tests: important behavior without a test, or a test that passes by construction.

Requirements:
R1. Every finding is verified by opening the code: cite `path:line`, quote the 1–3 offending lines, and give a concrete failure scenario (input/state → wrong result). No finding without a scenario. Where a scenario is cheap to run (a pure function, a script), run it and quote the output.
R2. Severity per finding: high (data loss, wrong behavior users hit, contract/boundary break, secret leak), medium, low.
R3. Report defects only; style preferences and "could be refactored" stay out.
R4. Read-only: the only file you write is OUTPUT_FILE. Other agents may run installs/tests in the same directory: ignore node_modules churn.
R5. Impact: for every changed export, enum value and string key (event, route, query/cache key, i18n, config), find its usages outside the diff with `rg` and check each against the change. A usage the change breaks is a finding.

Payload (OUTPUT_FILE), in this shape:
```
# Review: <BRANCH>
## Findings
### F1 [high] <one-line claim> — `path:line`
Quote: ...
Scenario: ...
Axis: A1..A6
...
## Checked, no issue
- one line per area you examined and found clean
## Impact checked
- `<symbol or key>`: <N> usages outside the diff, consistent | F<n>
```

Done when: OUTPUT_FILE has findings ranked high → low; SUMMARY gives counts per severity and the top 3 one-liners.

OUTPUT_FILE: <a path outside the repository; omit this line when sending through `hd ask`, which appends its own>

