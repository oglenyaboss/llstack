# llstack

How I work with coding agents every day. Agents write the code; a script decides when a task is done.

1. **Before work.** An issue reaches an agent only after its facts are checked against the code at a pinned commit, its acceptance cases are written and the owner's decision is quoted. [issue-workflow](skills/issue-workflow/SKILL.md)
2. **The task.** The brief settles every decision, names the traps and ends with a Check command, so a cheap model has nothing left to guess. [brief](skills/brief/SKILL.md)
3. **The run.** The executor's "done" is a claim. `hd` runs the brief's Check itself, lists every file changed outside the brief's Scope, shows the exact diff of that task and logs it. One expensive model leads, cheap ones do the work in Herdr panes. [herdr-delegate](skills/herdr-delegate/SKILL.md)
4. **Review.** A script maps the diff onto a path table: low, medium or high. The tier sets how many reviewers look, from which model families, and what has to pass before merge. [pr-risk](skills/pr-risk/SKILL.md)
5. **Mistakes.** Every rework gets one question: which step should have caught it? A finding caught twice becomes a check.

Only step 3 needs Herdr. The rest works in pi, Claude Code or Codex as is.

A worker saying "done", a merged PR, a deploy and the owner's acceptance are four separate events. Only the last one closes an issue.

Also here: [my global rules for agents](rules/AGENTS.md) (look for an existing solution before writing code, change only what the task needs, prove the result, ask before anything irreversible), [github-projects-api](skills/github-projects-api/SKILL.md) (GitHub Projects v2 through `gh` with the API limits I ran into) and [unslop](skills/unslop/SKILL.md) (removes AI writing tells and vague jargon from outward-facing prose).

## Harnesses

My daily driver is **pi**. Harness-specific packages, extensions and settings live under `harnesses/` so the root [INSTALL.md](INSTALL.md) stays agent-agnostic:

- **[pi](harnesses/pi/INSTALL.md)**: `pi install` package list (web access, cache optimizer, Archimedes UI/diff, resume-after-compact, peak hours, bg-bash, [pi-status-anim](https://github.com/oglenyaboss/pi-status-anim)), local extensions ([astra-guidance.ts](harnesses/pi/extensions/astra-guidance.ts) for OpenAI/GPT models and [archimedes-diff.ts](harnesses/pi/extensions/archimedes-diff.ts) bridge for `@pi-archimedes/diff`), plus clean reference configs for `settings.json`, `mcp.json` and `web-search.json`.
- **[Claude Code](harnesses/claude-code/INSTALL.md)**: profile skill links, context-saving settings, compact hook and optional tool denials for `herdr-delegate`.
- **[Codex](harnesses/codex/INSTALL.md)**: shared `~/.agents/skills` layout, `AGENTS.md` and `herdr-delegate` client notes.

Alongside llstack's own skills, [INSTALL.md](INSTALL.md) also offers the upstream skills I use daily: [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) and `frontend-design` from [anthropics/skills](https://github.com/anthropics/skills) (Apache 2.0).

## From my journal

`hd` writes a line per task. From 9 to 14 November 2026:

- 188 delegated tasks: 110 to workers, 35 to scouts, 25 to the sidekick, 18 to researchers.
- 154 of them (82%) ran on DeepSeek V4.1 Flash. Claude was the lead.
- 35 times a worker stopped and asked for a decision instead of guessing.
- In 13 of 62 tasks with a Scope, `hd` flagged changed files outside it. Some were my own edits made in parallel: `hd` sees what changed, not who changed it.

## Install

Paste this into pi, Claude Code or Codex:

```text
Read https://raw.githubusercontent.com/oglenyaboss/llstack/main/INSTALL.md and set me up.
```

The agent checks what you have, asks which parts and harnesses you want and shows every change before making it. It clones this repo and links the skills and extensions into your harness, so `git pull` updates them. Linux and macOS; on Windows, use WSL.

By hand: clone the repo, link `skills/<name>` into `~/.agents/skills/` (or your harness's skills directory) and follow [INSTALL.md](INSTALL.md) and the matching `harnesses/<name>/INSTALL.md`.

## Tests

```sh
bash skills/herdr-delegate/tests/run.sh
node --test skills/pr-risk/tests/risk.test.mjs
```

`hd` runs against a fake `herdr`, so neither suite needs Herdr, a model or the network. CI runs both on Linux and macOS.

## Credits

The triage roles and the explore-then-confirm setup shape come from [Matt Pocock's skills](https://github.com/mattpocock/skills). The worker, scout and researcher prompts started from [Nico Bailon's pi-subagents](https://github.com/nicobailon/pi-subagents). `ponytail:` comments follow [ponytail](https://github.com/DietrichGebert/ponytail). Details and license texts: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). My pi status animation is a separate package, [pi-status-anim](https://github.com/oglenyaboss/pi-status-anim).

MIT, see [LICENSE](LICENSE).
