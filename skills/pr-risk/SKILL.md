---
name: pr-risk
description: "Review depth and merge gates from a change's risk tier: Low, Medium or High. Use when reviewing, merging, or setting up PR risk tiers and review policy."
---

# PR risk

Review depth and merge gates follow the risk of the change. Compute the tier from the diff before review and again before merge. [references/review-policy.md](references/review-policy.md) holds the gates; this file covers the classifier and how to run the review.

## Project values

Read the `Workflow` section of the project's agent instructions (CLAUDE.md or AGENTS.md): decision owner, base branch, check, e2e and post-deploy commands, reviewer models. These values bind the policy to the project; they never weaken a gate. When a value you need is missing, ask the owner and record the answer in that section. A command you have not seen run in the repo or its CI is not a value.

Without that section, the base is `origin/HEAD` and the owner is the user you are working for.

## Classify

From the project:

```sh
node <this skill's directory>/scripts/risk.mjs --base <base branch>
```

The first line is `low`, `medium` or `high`. High and Medium file groups follow when present; Low currently has only the tier line. Exit 0 means classified, 1 means it could not classify, 2 is a usage error. A nonzero exit is never Low.

```sh
node .../scripts/risk.mjs --base origin/main                      # default table: .github/risk-tiers.yml
node .../scripts/risk.mjs --base origin/main --config ci/tiers.yml # another table, rooted at the project
```

A relative `--config` is read from the project root. Unknown arguments fail rather than silently selecting the default base.

## Review

Medium gets one reviewer. High gets two from different model families, plus the strong reviewer when the change spans several services. Give each reviewer [references/review-brief.md](references/review-brief.md), filled in, and run it with whatever your client offers: a subagent, another agent CLI, or `herdr-delegate` scouts. Open 1–3 cited `file:line` per reviewer before trusting its findings, then merge them into one row per root cause: finding, severity, who found it, verified.

## Act on the tier

- You may raise the tier, never lower it. Policy changes require explicit approval based on recorded rework evidence, not an exception for an inconvenient PR.
- A tier above the issue's expected risk stops work before review. Tell the owner; the change may have left its scope.
- Follow the policy's gate table and rules for review rounds, evidence, PR separation, hotfixes, release PRs and findings.
- When the Workflow section marks e2e or post-deploy as not set up, a High change waits for the owner to supply that procedure before merge.
- Store recurring findings in the project's `docs/agents/recurring-findings.md`. Review briefs point at that file when it exists.

## Adopt it in a project

Copy [references/risk-tiers.example.yml](references/risk-tiers.example.yml) to `.github/risk-tiers.yml` and replace its paths with the project's own, agreed with the owner. Keep `.github/risk-tiers.yml` itself in High, so a change to the table cannot lower its own tier.

## Classifier limits

The script reads git and one path table. It writes no files and makes no network or model calls.

- Globs: `**` crosses directories, `*` stays inside one path segment, `?` is one character. High wins over Low; unmatched paths are Medium. Empty diff is an error.
- The supported YAML subset is a high/low mapping to block lists of glob strings or empty flow lists such as `low: []`. Unsupported structures, duplicate tiers and malformed quoting fail closed.
- Only tracked changes enter the diff. A new file needs `git add -N <path>` before classification.
- Requires git and Node 18 or newer.

This classifier and written policy do not enforce branch protection. A hand-typed tier overrides nothing. The policy's Enforcement section describes a possible future push gate, not an installed one.

## Tests

```sh
node --test skills/pr-risk/tests/risk.test.mjs
```
