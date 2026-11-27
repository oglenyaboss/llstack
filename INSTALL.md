# Install llstack

You are installing llstack for the user you are talking to. Each step ends with a report to the user. Every write waits for the user's yes on the exact change you show: the command, the file and the lines.

## 1. Look

Collect, read-only:

- OS: `uname -s`.
- Tools: `bash -c 'echo $BASH_VERSION'` (the `bash` on PATH), `git --version`, `jq --version`, `node --version`, `gh auth status` (no other `gh` calls), and on macOS whether `timeout` or `gtimeout` is on PATH.
- Harnesses: which of `pi`, `claude`, `codex` are on PATH. Config directories: pi `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}`, Claude Code `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` plus every other `$HOME/.claude*` directory with a `settings.json` (each is a profile), Codex `~/.codex`. For each, note which of `skills/`, `extensions/`, `settings.json`, `CLAUDE.md` or `AGENTS.md` are symlinks and where they point.
- Skill directories: `~/.agents/skills` (pi and Codex both read it), each Claude Code `<config dir>/skills`, and the older `<pi dir>/skills` and `~/.codex/skills`. List the skills in each and where each one points.
- ZCode executor: `command -v zcode`, `zcode --version`, and whether this file exists with a `defaultModelSelection`: `${ZCODE_PERSONAL_PROVIDER_CONFIG_FILE:-${ZCODE_DATA_BASE_DIR:-$HOME}/.zcode/v2/provider_config.json}`. Show only its provider and model IDs, never its keys.
- Herdr: `herdr --version`, `herdr integration status`, and whether this session runs inside Herdr (`HERDR_ENV=1`).

Done when every line has a value or "absent". Show the table.

## 2. Choose

Present the parts with your recommendation, based on step 1, and ask which to install:

| Part | What it gives | Needs |
| --- | --- | --- |
| `issue-workflow` skill | capture -> fact-checked readiness -> execution -> acceptance on GitHub Issues | git, gh |
| `brief` skill | a standalone brief for any executor (subagent, another agent) and how to verify its result | nothing |
| `pr-risk` skill | review depth and merge gates from the diff's risk tier | git, node 18+ |
| `github-projects-api` skill | GitHub Projects v2 through `gh` | gh; only for teams that plan on a board |
| `unslop` skill | edits outward-facing prose to remove AI patterns and vague jargon | nothing |
| `herdr-delegate` skill | the lead briefs and verifies, workers run in Herdr panes, `hd` runs each brief's Check and lists files outside its Scope | the `brief` skill (and `pr-risk` for reviews), Herdr, bash 4.4+, jq, git 2.31+, `timeout` or `gtimeout`, and one configured executor: pi with a provider, or ZCode with a personal API-key provider ([setup](skills/herdr-delegate/executors/zcode.md)). On macOS: `brew install bash coreutils jq` |
| external skills | upstream skills used alongside llstack: `mattpocock/skills` (MIT) and `frontend-design` from `anthropics/skills` (Apache 2.0) | git or npx |
| harness setup | packages, extensions and settings for each chosen harness: [pi](harnesses/pi/INSTALL.md), [Claude Code](harnesses/claude-code/INSTALL.md), [Codex](harnesses/codex/INSTALL.md) | the harness binary |
| rules | the working rules in `rules/AGENTS.md`, for the user's global agent instructions | nothing |

Offer `herdr-delegate` only when step 1 found its requirements, or the user installs them now.

Also ask which harnesses are leads: the agents the user talks to directly, and for Claude Code, which profiles. Skills go to leads only; `hd` starts its workers without skills.

Done when the user has picked parts and leads.

## 3. Get the files

1. Ask where the clone should live (suggest `~/.local/share/llstack`) and run `git clone https://github.com/oglenyaboss/llstack <dir>`. When you are reading this file from a local checkout, use that checkout as `<dir>`. The links below point into it, so it stays at that path.
2. For each chosen llstack skill, link `<dir>/skills/<skill>` into `~/.agents/skills/` when a lead is pi or Codex (both read it). Claude Code skill linking is handled in [harnesses/claude-code/INSTALL.md](harnesses/claude-code/INSTALL.md). For any other agent, ask the user for its skills directory. When a skill of the same name already exists in any skill directory from step 1, show what it is and ask: replace or keep. Replace moves it to `<agent dir>/llstack-backup/<skill>`, outside the skills directory, so the agent does not load it twice.
3. Only when external skills were chosen: ask whether the user wants all of `mattpocock/skills` or a subset, and whether they want `frontend-design` from `anthropics/skills`. Install them globally into `~/.agents/skills/` from their upstream repos (for example via `npx -y skills add -g mattpocock/skills` and `npx -y skills add -g anthropics/skills --skill frontend-design`, or by cloning and linking the skill folders). Show the exact command before running it.

Done when `<dir>` is cloned and, if pi or Codex was chosen (or external skills were installed into `~/.agents/skills/`), `ls -l ~/.agents/skills/` shows every chosen llstack link resolving into `<dir>` and any chosen external skills present. (Claude Code-only skill links are checked in step 4.)

## 4. Harness setup

For each chosen lead harness, read and follow its own install guide:

- pi: [harnesses/pi/INSTALL.md](harnesses/pi/INSTALL.md)
- Claude Code: [harnesses/claude-code/INSTALL.md](harnesses/claude-code/INSTALL.md)
- Codex: [harnesses/codex/INSTALL.md](harnesses/codex/INSTALL.md)

Done when each chosen harness guide finishes its checks.

## 5. Delegation

Only when `herdr-delegate` was chosen.

1. Ask which executor the agents use: pi (every role), or ZCode (every role in a persistent TUI; [setup and limits](skills/herdr-delegate/executors/zcode.md)). Codex stays the scout executor. Require the chosen one to be configured: pi with a provider, or ZCode with `zcode` on PATH and a readable personal provider file. When neither is configured, stop and show what is missing.
2. Install the Herdr integration only for a pi executor: when `herdr integration status` shows the pi integration missing, propose `herdr integration install pi`. ZCode has no Herdr integration to install; its hooks report state to Herdr.
3. Ask which harness, model and thinking level the agents should use, which roles differ from that, and which models to fall back to when a provider fails. Write the answers to `${XDG_CONFIG_HOME:-$HOME/.config}/hd/config.json` in the format of the skill's [Configuration](skills/herdr-delegate/SKILL.md#configuration) section: `default` for every role, `slots` for the roles that differ (`researcher`, `reviewer`, `review-a`, `review-b`, `skeptic`), `fallback` for replacement models, `providers` for the pi extension each pi provider needs. pi model names stay as `pi --list-models` prints them; ZCode takes `providerId/modelId` and a thinking level only if the model supports it. Credentials stay in the executor's own config: pi's provider config or the personal ZCode provider file. A researcher on pi needs a web-search extension in its slot's `pi_extensions` (for example `~/.pi/agent/npm/node_modules/pi-web-access/index.ts`); without one it does not spawn. When a lead's environment still sets the `HD_*` variables that carried harness, model, thinking or pi extensions before the config file (for Claude Code, the `env` object in each profile's `settings.json`), show where and propose removing them: `hd` refuses to spawn while they are set.

Done when the config file passes `jq empty`, no lead's environment sets an `HD_*` variable from step 3, and the Herdr integration state reads back.

## 6. Rules

Only when rules were chosen.

Show `<dir>/rules/AGENTS.md` and ask which sections the user wants. Append the chosen sections to each lead's global instructions: pi `<pi dir>/AGENTS.md`, Claude Code `<config dir>/CLAUDE.md`, Codex `~/.codex/AGENTS.md`. Existing content stays as it is. When an existing rule contradicts one of ours, show both and let the user pick. When the user talks to agents in another language, offer to translate or add their own words to the action modes.

Done when each chosen file contains the chosen sections exactly once.

## 7. This repository

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

## 8. Verify

- Every llstack skill link: `ls <link>/SKILL.md`, and `readlink <link>` names a path inside `<dir>`, not another agent's skills directory (two directories linking to each other form a loop that no agent can read).
- Every chosen external skill: `ls <skill>/SKILL.md` succeeds, and if it is a symlink, `readlink <skill>` resolves to its upstream clone without looping back to another agent's skills directory.
- Every pi extension link (when pi was chosen): `readlink <link>` resolves inside `<dir>/harnesses/pi/extensions/`.
- `herdr-delegate`: inside Herdr, `<dir>/skills/herdr-delegate/hd` with no arguments prints its usage.
- `pr-risk`: in a git repository, run it through the link, the path agents will use: `node <link>/scripts/risk.mjs --base origin/HEAD`, adding `--config <link>/references/risk-tiers.example.yml` when the repository has no `.github/risk-tiers.yml`. It prints a tier, or `empty diff: nothing to classify` on a clean branch. Silence means it did not run.
- Every settings/config file you touched passes `jq empty`.

Then tell the user what went where, the backup paths, any pi packages newly installed (for later `pi remove` if needed), what was skipped, and that the skills appear in the next new session.

## Update and remove

- Update: `git -C <dir> pull` (and `pi update` for pi packages). The links pick up the changes. If an older install linked `<dir>/pi/extensions/astra-guidance.ts`, repoint that symlink to `<dir>/harnesses/pi/extensions/astra-guidance.ts`.
- Remove: run `pi remove <source>` for each pi package installed during setup, delete the links and the clone, move items back from `llstack-backup/`, restore `*.bak-llstack` config files (and delete newly created config files that had no backup), and remove the rules sections you appended.
