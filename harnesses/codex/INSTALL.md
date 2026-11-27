# Install llstack for Codex

Run this after the shared skill and rules steps in [../../INSTALL.md](../../INSTALL.md). Every write waits for the user's yes on the exact change you show: the command, the file and the lines.

## 1. Skills

Codex reads `~/.agents/skills/` directly, so the links created in step 3 of the root `INSTALL.md` work without extra steps.

If `~/.codex/skills/` also has older copies of the same skill names, show them and ask whether to move duplicates to `~/.codex/llstack-backup/` so Codex does not load a skill twice.

## 2. Rules

Global rules from [../../rules/AGENTS.md](../../rules/AGENTS.md) go into `~/.codex/AGENTS.md` (handled by step 6 of the root `INSTALL.md`).

## 3. Delegation notes

When `herdr-delegate` is used from Codex CLI (`functions.exec`), follow [../../skills/herdr-delegate/clients/codex.md](../../skills/herdr-delegate/clients/codex.md) for launching and waiting on `hd ask`.
