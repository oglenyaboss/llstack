---
name: brief
description: "Standalone brief for a subagent or another agent, and how to verify its result against it. Use when handing a coding task to an executor."
---

# Brief

The executor sees none of your conversation, copies well, invents badly, and follows the brief literally. The result is only as good as the brief, and an error in the brief passes your verification, because you verify against that same brief.

## Format

Write the brief to a file. Give the executor something to copy:

```
Goal: one sentence, the observable result.
Context:
- pointers: `path:line-range` for every fact that lives in a file, a pattern to copy
  ("as in `foo.ts:40-60`"), payload paths to read first, exact names of new functions and files
- any existing test the change breaks, named here
Decisions:
- D1: what you chose where the files leave a choice open
- D2: ...
Requirements:
- R1: one observable behavior
- R2: ...
Removes: what the change takes away or replaces (a screen, a key, a route, a flag, a fallback), each with
         an Acceptance case proving it is gone; "nothing" when nothing goes.
Traps:
- where a plausible implementation goes wrong, with the correct shape: the check and the write it guards
  in one transaction (`SELECT … FOR UPDATE`), a second concurrent caller, the first/last/empty index
Acceptance:
- Seam: the seam under test (public function, endpoint, component)
- R1: <concrete input> → <exact expected literal>
- Trap: <edge input> → <exact expected result>
Scope: `src/a.ts` `src/auth/` `tests/*.test.ts`
Done when: exact command and expected output ("pnpm test slug → 13 passed"); the report shows each case red, then green.
Check: `one shell command` proving Done when.
```

A brief is an executable spec, not a summary: every Decision, Requirement, Trap, and Acceptance case gets its own line with concrete literals (UI strings, keys, status codes, payloads), never shorthand such as "tests for R1–Rn", and an existing test that blocks the change is named explicitly in `Context`, `Decisions`, and `Scope`. `Scope` stays one line of specific repo-relative paths in backticks, because `hd` reads that line; a directory only when the task owns the whole directory.

Done when an executor with zero context could carry out the brief without guessing.

Acceptance is TDD done in the brief: you pick the seam and the cases, the executor runs red → green. A case tests behavior through the seam, never internals; an expected value recomputed the way the code computes it is tautological and passes by construction. An existing test that blocks the change is an open choice, never a deletion.

**Pointers over prose.** A fact that lives in a file reaches the brief as a pointer with "copy as is"; prose carries only what no file holds: decisions, deviations, traps. A retelling is a second source of truth, the executor follows the more concrete one, and every drift in your retelling ships as a defect.

The executor gets right what the brief names and misses what it leaves out, so correctness lives in Traps and Acceptance: spend your code reading on finding the traps. A pointer "as in X" hands over X's behavior with its edge cases: check they fit this task. One task per brief. A task spanning more than a few files becomes sequential briefs, each verified before the next. Brief only from code and payloads you read in this session.

## Verify

Every claim in the executor's report is unverified until you see its evidence. Done when:

- you ran Check yourself and saw exit 0 and the expected output; the executor's own run is a claim, not evidence;
- the diff touches no file outside Scope;
- you read the diff against the brief: every R has its hunk, every Acceptance case its passing test unchanged from the brief, every called API exists, every assumption the executor reports is one you would make.

When the executor asks for a decision, or the brief turns out to contradict the code, the fix goes into the brief: answer, correct the brief, and send it again with Scope and Check repeated.
