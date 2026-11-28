Goal: <one sentence, the observable result>

Context:
- checked at `<sha>`
- <fact> → `path/to/file:line`
- pattern to copy: `path/to/file:start-end` (or `none`)
- existing tests affected: `path/to/test` (or `none`)

Decisions:
- Owner: <verbatim answer from the decision owner, or "Not required: <one line why>". ADR link when the decision constrains future behavior.>
- D1: <technical choice where the code leaves a choice open, or omit if none>

Requirements:
- R1: <one observable behavior>
- R2: <one observable behavior>

Removes: <what is removed or replaced, or "nothing">

Traps:
- <where a plausible implementation goes wrong, with the correct shape> (or `none — <reason>`)

Acceptance:
- Seam: <public function, endpoint, component, or CLI command>
- R1: <concrete input> → <exact expected literal>
- Trap: <edge input> → <exact expected result>

Scope: `path/to/file` `tests/file.test.ts`
Check: `<one shell command proving Done when>`

---
Expected risk: <low | medium | high> via `<paths that matched .github/risk-tiers.yml>`
Size: <xs | s | m>
