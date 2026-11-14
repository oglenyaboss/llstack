# Sources

Component-level provenance for the issue workflow skill. The repository's THIRD_PARTY_NOTICES.md carries the license text.

## Author's private process docs

Source: an internal set of agent docs, used with permission and kept out of this repository: a process page, an issue-tracker page, a triage-label page, an estimation page, and a review page.

Kept as behavior:

- capture and readiness are separate steps, and capture writes no acceptance criteria;
- readiness requires checking facts at the current base commit, writing acceptance cases, recording the owner's decision verbatim, and estimating risk;
- the decision conditions: more than one visible behavior, an invariant, a reversal of chosen behavior, scope, a fix that cannot be derived;
- a failed fact or an unrecorded decision returns the issue to `needs-info` instead of becoming a guess in a brief;
- native issue dependencies with database ids, and a frontier of open, unblocked, unassigned issues;
- size measured in human attention, with `xs`/`s`/`m` and larger work split;
- the `rework` marker and the question of which layer should have caught the rework;
- one review round, and a fix re-review only on high risk.

Changed:

- the weekly cadence, the Monday and Friday meetings, the PM role, week-number fields, and the product-area labels are gone. a decision owner role replaces a named person, and a cycle is counted in slots with a count chosen at the start.
- product names, org names, project ids, absolute paths, and the author's handle are removed.
- label strings default to the role names and can be mapped in the project's Workflow section.
- the state list is limited to the five triage roles plus `rework`; board status is documented as a separate axis.
- the completion ladder is explicit. The source docs contained both an automation that closed an issue on merge and a rule that the owner accepts before work is done. This build resolves the contradiction in one direction: a merged PR does not close the issue, and closing waits for a declared acceptance. The old automation is not reproduced or claimed to have been verified.
- the review policy moved out: `pr-risk` owns it, and this skill only estimates a tier.

## Matt Pocock's triage roles

Source: Matt Pocock's public skills repository, `docs/engineering/triage.md` and the `triage` skill docs, MIT License, copyright 2026 Matt Pocock.

Kept:

- the five role names, `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`;
- exactly one state role per item;
- the idea that the strings are local and the roles are canonical.

Changed:

- `ready-for-agent` here also requires the base-commit fact check, the recorded owner decision, and the risk estimate. Matt's role means fully specified with a brief; this one adds the verification that the author's process demanded.
- `wontfix` keeps a one-line reason in a comment. Matt's `.out-of-scope/` concept files are not part of this skill.
- no PR diff or external-request workflow is copied. External PRs stay out of the triage path.

## Not copied

No session logs, client data, account ids, or board ids from either source appear here.
