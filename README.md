# llstack

The coding-agent workflow I use every day. One agent is the lead. It decides, writes briefs and checks results, while cheaper models do the work in Herdr panes I can watch. Issues get their facts checked before anyone starts on them, and review depth follows the risk of the diff.

| Part | What it does |
| --- | --- |
| [herdr-delegate](skills/herdr-delegate/SKILL.md) | Lead mode. `hd` starts pi workers, scouts, a sidekick and researchers in Herdr panes. After each task it runs the brief's Check command, lists files changed outside the brief's Scope, shows the exact diff of that task and appends a line to a journal. |
| [pr-risk](skills/pr-risk/SKILL.md) | `risk.mjs` matches the diff against `.github/risk-tiers.yml` and prints low, medium or high. [The policy](skills/pr-risk/references/review-policy.md) maps each tier to reviewers, evidence and merge gates. |
| [issue-workflow](skills/issue-workflow/SKILL.md) | An issue gets `ready-for-agent` only after every fact in it is checked against a pinned commit, acceptance cases are written and the owner's decision is quoted. |
| [github-projects-api](skills/github-projects-api/SKILL.md) | GitHub Projects v2 through `gh`, with the API limits I ran into. |
| [rules](rules/AGENTS.md) | My global rules for agents: look for an existing solution before writing code, change only what the task needs, prove the result, ask before anything irreversible. |

## Install

Paste this into Claude Code, Codex or pi:

```text
Read https://raw.githubusercontent.com/oglenyaboss/llstack/main/INSTALL.md and set me up.
```

The agent checks what you have, asks which parts you want and shows every change before making it. It clones this repo and links the skills into your agent, so `git pull` updates them. Linux and macOS; on Windows, use WSL.

By hand: clone the repo, link `skills/<name>` into your agent's skills directory and follow [INSTALL.md](INSTALL.md) from step 4.

## The loop

```text
capture an issue
→ check its facts at the base commit, write acceptance cases, get the owner's decision
→ take ready work that nothing blocks
→ brief a worker
→ read the Check output, the Scope report and the diff
→ review as deep as the risk tier asks
→ record rework and turn repeated findings into checks
```

Most of the effort goes into the brief. Workers copy well and invent badly, and the lead verifies against the same brief, so a mistake in it passes verification. The format makes the lead settle every decision, name the traps and write the acceptance cases up front: [Standalone brief](skills/herdr-delegate/SKILL.md#standalone-brief).

A worker saying "done", a merged PR, a deploy and the owner's acceptance are four separate events. Only the last one closes an issue.

## My Claude Code settings

```json
{
  "syncClaudeAiSkills": false,
  "disableClaudeAiConnectors": true,
  "disableBundledSkills": true,
  "enableArtifact": false,
  "promptSuggestionEnabled": false,
  "awaySummaryEnabled": false,
  "autoMemoryEnabled": false,
  "skillOverrides": {"<rarely used skill>": "name-only"}
}
```

Each key turns off a feature I don't use and the context it loads. `name-only` keeps a skill in the listing without its description. With these and the denied tools from [INSTALL.md](INSTALL.md) step 4, the first request of a session went from about 40k input tokens to about 13k on my machine. That was across Claude Code 2.1.306 to 2.1.322 and different projects, so treat it as an observation, not a benchmark. Keep the features you use.

## Tests

```sh
bash skills/herdr-delegate/tests/run.sh
node --test skills/pr-risk/tests/risk.test.mjs
```

`hd` runs against a fake `herdr`, so neither suite needs Herdr, a model or the network. CI runs both on Linux and macOS.

## Credits

The triage roles and the explore-then-confirm setup shape come from [Matt Pocock's skills](https://github.com/mattpocock/skills). The worker, scout and researcher prompts started from [Nico Bailon's pi-subagents](https://github.com/nicobailon/pi-subagents). `ponytail:` comments follow [ponytail](https://github.com/DietrichGebert/ponytail). Details and license texts: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). My pi status animation is a separate package, [pi-status-anim](https://github.com/oglenyaboss/pi-status-anim).

MIT, see [LICENSE](LICENSE).
