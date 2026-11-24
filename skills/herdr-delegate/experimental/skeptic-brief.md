Goal: disprove that the diff does what the spec asks: a ranked list of verified defects with file:line, or the verdict that you could not break it.

Context (read first):
- Spec: <issue number or file path, plus the user's decisions from this session quoted verbatim>. This is the only statement of intent you get.
- Diff under attack: `<path to the patch>`. The surrounding code is the working tree in your cwd.
- Project rules: <CLAUDE.md / AGENTS.md sections that define invariants, or "none">.

Attacks, in this order:
S1. Spec drift: a requirement of the spec missing, narrowed, or implemented differently; behavior the spec did not ask for.
S2. Inputs: first/last/empty, null, duplicates, the same request twice, malformed or hostile input.
S3. Concurrency and state: two callers at once, a check and the write it guards outside one transaction, failure halfway through, retries.
S4. Callers: every changed export, enum value, and string key (event, route, query/cache key, config) used outside the diff, found with `rg` and checked against the change.
S5. Tests: a test that passes by construction, a spec requirement without a test.

Requirements:
R1. Every finding cites its location on one line as `` `path:line` — `offending line` ``, the line copied from the file, and gives a concrete scenario (input/state → wrong result). Where the scenario is cheap to run (a test, a script), run it and quote the output.
R2. Severity per finding: high (data loss, wrong behavior users hit, security), medium, low. Defects only; style stays out.
R3. Leave the working tree exactly as you found it: scratch files go next to OUTPUT_FILE.

Payload (OUTPUT_FILE), in this shape:
```
# Skeptic: <task>
## Verdict
broken | could not break
## Findings
### F1 [high] <one-line claim>
`path:line` — `offending line`
Scenario: ...
Run: <command and output | not run>
Confidence: high | medium
Attack: S1..S5
## Attacked, held
- one line per attack that found nothing, naming what you tried
```

With no findings, `## Findings` holds exactly `No findings.`

Done when: each of S1–S5 has a finding or an "Attacked, held" line; SUMMARY gives the verdict, counts per severity, and the top 3 one-liners.
