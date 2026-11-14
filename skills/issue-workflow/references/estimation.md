# Estimates

An issue's size measures human attention, not code volume and not elapsed time. A model writes a large diff in minutes; a person still has to read it, run the flow, and accept the result. That attention is the bottleneck, so it is what the size describes.

## Scale

| Size | Weight | What it requires |
|---|---|---|
| `xs` | about half an `s` | The decision is obvious, the edit is local, review plus one check. Still needs acceptance cases. |
| `s` | one unit | Written statement plus acceptance cases; an agent can carry it from there. |
| `m` | about two `s` | A short spec or plan before code, review, an e2e run, acceptance. |
| larger | not allowed as a task | Split into `s` and `m` before it enters a cycle. |

An `xs` is a slot filler, not a way to skip the acceptance section. If you cannot write an observable acceptance case, the issue is not sized yet.

## Slots

A planning cycle is counted in slots, not hours.

```
1 slot = 1 m | 2 s | 2 s + 1 xs
```

The number of slots in a cycle is a decision made at the start of the cycle from the work available and the time the people involved actually have. It is not a fixed hour budget and not a fixed weekday ritual. A cycle that commits to sixteen slots and closes nine has learned something; a cycle that commits to "as much as possible" has not.

Triage, review, and acceptance are inside an issue's estimate, not separate lines. That is why the estimate is attention: those activities are the attention.

## Rules for agents

1. Size by what a person must check and integrate, never by "this will take a day". Correct: "`s`: review plus one e2e run". Wrong: "about a day of work".
2. Every planned item is `xs`, `s`, or `m`. Anything larger is split.
3. Do not size a container issue. Size appears after decomposition, and the total is converted to slots.
4. Size after readiness, not at capture. A claim that has not been checked cannot be sized.

## Where the size lives

A label when the repo has size labels (`size:xs`, `size:s`, `size:m`, or whatever the repo uses), otherwise a `Size` line in the issue body.

## Calibration

Historical issue lifetime is a bad estimator: most of it is queue time. Calibrate forward instead. At the end of each cycle, record how many slots were committed and how many closed, and whether the mix of `rework` matched expectations. Adjust the next commitment.

Two signals matter:

- Committed slots far above closed slots, repeatedly: the slot count is fiction, or the issues are sized too small.
- `rework` growing: the size is not the problem, the readiness gate is leaking, and the fix is upstream.

Absolute hours stay out of this. With agent-written code and a person's attention as the constraint, hours look precise and behave unpredictably. Relative weights survive contact with a real week.
