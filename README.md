# llstack

How I work with coding agents every day. Agents write the code; a script decides when a task is done.

1. **Before work.** An issue reaches an agent only after its facts are checked against the code at a pinned commit, its acceptance cases are written and the owner's decision is quoted. [issue-workflow](skills/issue-workflow/SKILL.md)
2. **The task.** The brief settles every decision, names the traps and ends with a Check command, so a cheap model has nothing left to guess. [brief](skills/brief/SKILL.md)
3. **The run.** The executor's "done" is a claim. `hd` runs the brief's Check itself, lists every file changed outside the brief's Scope, shows the exact diff of that task and logs it. One expensive model leads, cheap ones do the work in Herdr panes. [herdr-delegate](skills/herdr-delegate/SKILL.md)
4. **Review.** A script maps the diff onto a path table: low, medium or high. The tier sets how many reviewers look, from which model families, and what has to pass before merge. [pr-risk](skills/pr-risk/SKILL.md)
5. **Mistakes.** Every rework gets one question: which step should have caught it? A finding caught twice becomes a check.

Only step 3 needs Herdr. The rest works in Claude Code, Codex or pi as is.

A worker saying "done", a merged PR, a deploy and the owner's acceptance are four separate events. Only the last one closes an issue.

Also here: [my global rules for agents](rules/AGENTS.md) (look for an existing solution before writing code, change only what the task needs, prove the result, ask before anything irreversible) and [github-projects-api](skills/github-projects-api/SKILL.md), GitHub Projects v2 through `gh` with the API limits I ran into. [astra-guidance](pi/extensions/astra-guidance.ts) is a pi extension that adds working-style rules to the system prompt when the model is GPT-6.2 Astra: a final answer written for a person, open blockers listed, questions only where the user decides. Link it into `~/.pi/agent/extensions/`.

## From my journal

`hd` writes a line per task. From 9 to 14 November 2026:

- 188 delegated tasks: 110 to workers, 35 to scouts, 25 to the sidekick, 18 to researchers.
- 154 of them (82%) ran on DeepSeek V4.1 Flash. Claude was the lead.
- 35 times a worker stopped and asked for a decision instead of guessing.
- In 13 of 62 tasks with a Scope, `hd` flagged changed files outside it. Some were my own edits made in parallel: `hd` sees what changed, not who changed it.

## Install

Paste this into Claude Code, Codex or pi:

```text
Read https://raw.githubusercontent.com/oglenyaboss/llstack/main/INSTALL.md and set me up.
```

The agent checks what you have, asks which parts you want and shows every change before making it. It clones this repo and links the skills into your agent, so `git pull` updates them. Linux and macOS; on Windows, use WSL.

By hand: clone the repo, link `skills/<name>` into your agent's skills directory and follow [INSTALL.md](INSTALL.md) from step 4.

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
