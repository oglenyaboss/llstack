# Install llstack for Claude Code

Run this after the shared skill and rules steps in [../../INSTALL.md](../../INSTALL.md). Every write waits for the user's yes on the exact change you show: the command, the file and the lines.

`${CLAUDE_DIR}` below is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (repeat for each chosen profile directory `$HOME/.claude*`).

## 1. Skills

Claude Code reads `<profile>/skills/`, not `~/.agents/skills/`.

- Link each chosen llstack skill from `<llstack dir>/skills/<skill>` into `${CLAUDE_DIR}/skills/`.
- If external skills were installed into `~/.agents/skills/`, link them into `${CLAUDE_DIR}/skills/` too, or leave them out if the user only wants them in `pi`/Codex.
- Profiles that share a `skills/` directory through a symlink get one link, in the directory it resolves to.

## 2. Context-saving settings (optional)

These settings turn off Claude Code features the author does not use and cut initial session context:

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

Ask which keys the user wants. Keep any feature they actively use.

## 3. Delegation hooks and denials (only when `herdr-delegate` was chosen)

1. Offer the compact hook in `${CLAUDE_DIR}/settings.json`. After context compaction, it reminds the lead of its role and lists still-running agents:

   ```json
   {"hooks": {"SessionStart": [{"matcher": "compact", "hooks": [{"type": "command", "command": "bash <skills dir>/herdr-delegate/on-compact.sh", "timeout": 20}]}]}}
   ```

2. Optional. Offer the tool denials that route every delegation through `hd`:

   ```json
   {"permissions": {"deny": ["Agent", "AskUserQuestion", "ListAgents", "ReportFindings", "ScheduleWakeup", "SendFeedback", "Workflow"]}}
   ```

   Name the losses before asking: no in-process subagents, no structured question dialog, and any plugin that relies on one of these tools stops working. Recommend leaving this out of a first install; the skill works with those tools enabled.

Before editing `${CLAUDE_DIR}/settings.json`: copy it to `settings.json.bak-llstack`, merge into the existing JSON (keep other keys, append list entries), then confirm `jq empty settings.json` succeeds.

## 4. Rules

Global rules from [../../rules/AGENTS.md](../../rules/AGENTS.md) go into `${CLAUDE_DIR}/CLAUDE.md` (handled by step 6 of the root `INSTALL.md`).
