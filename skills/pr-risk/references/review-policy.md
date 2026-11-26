# Review and merge policy

How strictly a change is reviewed and merged depends on its risk, not on who wrote it. The tier comes from the diff. An agent may raise a tier, never lower it. Start strict. Change policy gates only after reviewing recorded rework evidence, not for convenience on one PR.

## Tiers

- **Low**: docs, markdown, styles, UI assets, e2e and unit tests outside the high paths.
- **Medium**: whatever is neither high nor low. UI features, admin APIs, agent tooling, dependencies.
- **High**: the paths where a wrong change hurts most. The main data path (whatever the product takes in, processes and delivers), shared libraries, auth, OAuth and secrets, payments, the database schema, infrastructure, deploy, CI workflows, git hooks, and the tier table itself.

The table is `.github/risk-tiers.yml`; the classifier is `scripts/risk.mjs` in this skill. A file is high if it matches `high`, low if it matches `low`, and medium otherwise. The tier of a change is the highest tier among its files. An empty diff is an error, not Low.

## Merge gates

| gate | Low | Medium | High |
| --- | --- | --- | --- |
| pre-push | yes | yes | yes |
| review | none | one reviewer | two reviewers from different model families; a change spanning several services adds the strong reviewer |
| evidence in the PR | none | test output, or a screenshot | test output, a screenshot, and how to roll back |
| e2e before merge | none | none | the affected specs, run locally with the project's e2e command |
| the owner | nothing; the lead merges | "ok" on the evidence, the diff stays unread | reads the diff of the risky paths, then "ok" on the exact commit |
| first hour after deploy | none | none | errors and the product's failure signals (failed jobs, deliveries, queue backlogs), watched and reported |

## Rules that hold across tiers

- The initial review round uses exactly the reviewer count the table names; do not split one round into extra thematic reviewers.
- One review round. Re-review is capped at one round: High only, the fix diff only, the first reviewer only. There is no third or fourth control round; the lead checks pinpoint follow-ups and escalates unresolved blockers to the owner.
- High e2e runs only the affected specs; a full suite needs a shared foundation change or the owner's request.
- An epic branch runs review and e2e gates once for the assembled epic PR, not per subtask; its children are accepted by the worker's `Check` and the lead's diff review.
- The owner's "ok" on High covers one commit. A new commit after that needs a new "ok".
- A change whose tier is above the risk its issue expected stops before review: the lead tells the owner, because the change probably left its scope.
- A High change goes in its own PR. Low and Medium tickets may share one.
- A hotfix into the default branch is always High.
- The release PR (release branch into the default branch) merges on green CI. A hotfix opened while a release PR is open lands as a sync PR first, then the release PR runs again.
- A slot that does not apply is never dropped silently. A backend-only High change has no UI to screenshot, so the owner approves that slot as not applicable and the lead records the approval in the PR.
- Findings of this PR close in this PR: a fix, or a reply with the reason. A finding outside the PR's scope becomes an issue only when it is high or medium with a concrete scenario. Low findings, and bugs that predate the PR, get one line in the PR description: known, not fixing.

## Recurring findings

A finding the review catches a second time moves to its source: a project rule, a lint, a test, or a trap in the brief. Record it in the project's `docs/agents/recurring-findings.md`, creating that file on the first occurrence. Review briefs read that list. This policy file stays the same across projects; findings live in the project.

## Project values

The policy text is generic; the `Workflow` section of the project's agent instructions (CLAUDE.md or AGENTS.md) supplies the concrete values.

| Workflow line | what it fills |
| --- | --- |
| Decision owner | "the owner" in the table |
| Base branch | what `--base` classifies against, and the branch a PR merges into |
| Check before push | the pre-push gate, and the test output in the evidence |
| E2E for High changes | the e2e command for the affected specs |
| First hour after a High deploy | what to watch during the first hour |
| Reviewers | the Medium reviewer and first High reviewer, the second High reviewer from a different model family, and the strong reviewer for changes spanning several services |
| `.github/risk-tiers.yml` | the tier table |

## Enforcement

The lead follows these gates. Nothing blocks a merge mechanically, and this policy assumes no branch protection. If the gates start getting skipped, the first mechanical step is a pre-push hook that refuses to push a High branch without a review marker. That hook is not part of this build.
