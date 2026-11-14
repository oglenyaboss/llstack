# Install llstack

You are installing llstack for the user you are talking to. Each step ends with a report to the user. Every write waits for the user's yes on the exact change you show: the command, the file and the lines.

## 1. Look

Collect, read-only:

- OS: `uname -s`.
- Tools: `bash -c 'echo $BASH_VERSION'` (the `bash` on PATH), `git --version`, `jq --version`, `node --version`, `gh auth status` (no other `gh` calls), and on macOS whether `timeout` or `gtimeout` is on PATH.
- Agents: which of `claude`, `codex`, `pi` are on PATH. Config directories: Claude Code `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` plus every other `$HOME/.claude*` directory with a `settings.json` (each is a profile), Codex `~/.codex`, pi `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}`. For each, note which of `skills/`, `settings.json`, `CLAUDE.md` or `AGENTS.md` are symlinks and where they point.
- Herdr: `herdr --version`, `herdr integration status`, and whether this session runs inside Herdr (`HERDR_ENV=1`).

Done when every line has a value or "absent". Show the table.

## 2. Choose

Present the parts with your recommendation, based on step 1, and ask which to install:

| Part | What it gives | Needs |
|---|---|---|
| `issue-workflow` skill | capture → fact-checked readiness → execution → acceptance on GitHub Issues | git, gh |
| `brief` skill | a standalone brief for any executor (subagent, another agent) and how to verify its result | nothing |
| `pr-risk` skill | review depth and merge gates from the diff's risk tier | git, node 18+ |
| `github-projects-api` skill | GitHub Projects v2 through `gh` | gh; only for teams that plan on a board |
| `herdr-delegate` skill | the lead briefs and verifies, workers run in Herdr panes, `hd` runs each brief's Check and lists files outside its Scope | the `brief` skill (and `pr-risk` for reviews), Herdr, pi with a configured provider, bash 4.4+, jq, git 2.31+, `timeout` or `gtimeout`. On macOS: `brew install bash coreutils jq` |
| rules | the working rules in `rules/AGENTS.md`, for the user's global agent instructions | nothing |

Offer `herdr-delegate` only when step 1 found its requirements, or the user installs them now.

Also ask which agents are leads: the agents the user talks to directly, and for Claude Code, which profiles. Skills go to leads only; `hd` starts its workers without skills.

Done when the user has picked parts and leads.

## 3. Get the files

1. Ask where the clone should live (suggest `~/.local/share/llstack`) and run `git clone https://github.com/oglenyaboss/llstack <dir>`. When you are reading this file from a local checkout, use that checkout as `<dir>`. The links below point into it, so it stays at that path.
2. For each chosen skill and each lead, link `<dir>/skills/<skill>` into the lead's skills directory: Claude Code `<config dir>/skills/`, Codex `~/.codex/skills/`, pi `<pi dir>/skills/`. For any other agent, ask the user for its skills directory. Profiles that share a skills directory through a symlink get one link, in the directory it resolves to. When a skill of the same name already exists there, show what it is and ask: replace or keep. Replace moves it to `<agent dir>/llstack-backup/<skill>`, outside the skills directory, so the agent does not load it twice.

Done when `ls -l` on each skills directory shows every chosen link resolving into `<dir>`.

## 4. Delegation

Only when `herdr-delegate` was chosen.

1. When `herdr integration status` shows the pi integration missing, propose `herdr integration install pi`.
2. Ask which model and thinking level pi workers should use. Model names only; credentials stay in pi's own config. Set them in the lead's environment as `HD_MODEL` and `HD_THINKING`. When the user has a pi web-search extension for the researcher role, add its path as `HD_PI_EXTENSIONS` (colon-separated). For Claude Code, the lead's environment is the `env` object in the `settings.json` of each chosen profile; for another lead, it is wherever that client's shell commands get their environment.
3. Claude Code only. Offer the compact hook: after the context compacts, it reminds the lead of its role and lists the agents still running.

   ```json
   {"hooks": {"SessionStart": [{"matcher": "compact", "hooks": [{"type": "command", "command": "bash <skills dir>/herdr-delegate/on-compact.sh", "timeout": 20}]}]}}
   ```

4. Claude Code only, optional. Offer the denials that make every delegation go through `hd`:

   ```json
   {"permissions": {"deny": ["Agent", "AskUserQuestion", "ListAgents", "ReportFindings", "ScheduleWakeup", "SendFeedback", "Workflow"]}}
   ```

   Name the losses before asking: no in-process subagents, no structured question dialog, and any plugin that relies on one of these tools stops working. Recommend leaving this out of a first install; the skill works with those tools enabled.

When editing `settings.json`: copy it to `settings.json.bak-llstack` first, merge into the existing JSON (other keys keep their values, lists get the new entries appended), then confirm `jq empty settings.json` succeeds.

Done when the env values, and the hook and denials the user accepted, read back from the settings file.

## 5. Rules

Only when rules were chosen.

Show `<dir>/rules/AGENTS.md` and ask which sections the user wants. Append the chosen sections to each lead's global instructions: Claude Code `<config dir>/CLAUDE.md`, Codex `~/.codex/AGENTS.md`, pi `<pi dir>/AGENTS.md`. Existing content stays as it is. When an existing rule contradicts one of ours, show both and let the user pick. When the user talks to agents in another language, offer to add their own words to the action modes.

Done when each chosen file contains the chosen sections exactly once.

## 6. This repository

Only when `issue-workflow` or `pr-risk` was chosen and the user wants the current repository set up.

1. Risk table: copy `<dir>/skills/pr-risk/references/risk-tiers.example.yml` to `.github/risk-tiers.yml`, then agree on the paths with the user. High holds the paths where a wrong change hurts most: auth, payments, schema and migrations, the main data path, deploy, CI. Low holds docs, assets and tests outside High. `.github/risk-tiers.yml` itself stays in High.
2. Labels: read them with `gh label list --limit 200`. When the repo already uses its own names for these roles, record the mapping in the Workflow section instead. For each missing role, propose:

   ```sh
   gh label create needs-triage    --description "Captured, facts not checked yet"
   gh label create needs-info      --description "Waiting on an owner decision or a failed fact"
   gh label create ready-for-agent --description "Facts checked, acceptance written, an agent can take it"
   gh label create ready-for-human --description "Ready, needs a human"
   gh label create wontfix         --description "Will not be done; reason in a comment"
   gh label create rework          --description "Redone, reverted or hotfixed after merge"
   ```

3. Workflow section: add it to the repo's agent instructions, `CLAUDE.md` when it exists, otherwise `AGENTS.md`. Fill it from the repo (CI config, package scripts, Makefile) and the user's answers:

   ```markdown
   ## Workflow

   - Decision owner: <name or role>
   - Base branch: origin/<default branch>
   - Labels: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix, rework
   - Risk table: .github/risk-tiers.yml
   - Check before push: `<command>`
   - E2E for High changes: `<command>` | not set up
   - First hour after a High deploy: <what to watch> | not set up
   - Reviewers: <model A>, <model B> (another family); strong: <model C>
   - GitHub Project: <owner>/<number> | none
   ```

   A command goes in only when you have seen the repo or its CI run it; anything else is `not set up`, and a High merge then waits for the owner.

Done when `.github/risk-tiers.yml` exists, every role has a label, and the Workflow section has a value or `not set up` on every line.

## 7. Verify

- Every link: `ls <link>/SKILL.md`.
- `herdr-delegate`: inside Herdr, `<dir>/skills/herdr-delegate/hd` with no arguments prints its usage.
- `pr-risk`: in a git repository, run it through the link, the path agents will use: `node <link>/scripts/risk.mjs --base origin/HEAD`, adding `--config <link>/references/risk-tiers.example.yml` when the repository has no `.github/risk-tiers.yml`. It prints a tier, or `empty diff: nothing to classify` on a clean branch. Silence means it did not run.
- Every settings file you touched passes `jq empty`.

Then tell the user what went where, the backup paths, what was skipped, and that the skills appear in the next new session.

## Update and remove

- Update: `git -C <dir> pull`. The links pick up the change.
- Remove: delete the links and the clone, move skills back from `llstack-backup/`, restore `settings.json.bak-llstack`, and remove the rules sections you appended.
