# Install llstack for pi

Run this after the shared skill and rules steps in [../../INSTALL.md](../../INSTALL.md). Every write waits for the user's yes on the exact change you show: the command, the file and the lines.

`${PI_DIR}` below is `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}`.

## 1. Skills visibility

`pi` reads `~/.agents/skills` automatically. Check `${PI_DIR}/settings.json`: if its `skills` array excludes `~/.agents/skills` (or any skill chosen from llstack), show the entry and ask to narrow it; otherwise `pi` will not load those links.

## 2. Packages

Show this list and ask which packages to install with `pi install <source>`:

| Package | What it does |
| --- | --- |
| `npm:pi-web-access@0.28.0` | web search and page fetch tools (also used by the `researcher` role in `herdr-delegate`) |
| `https://github.com/DanielVASE/pi-resume-after-compact` | resumes work cleanly after context compaction |
| `npm:pi-cache-optimizer` | optimizes prompt cache usage |
| `npm:@pi-archimedes/core` | Archimedes UI core |
| `npm:@pi-archimedes/footer` | Archimedes footer bar |
| `npm:@pi-archimedes/diff` | diff renderer library (needs the `archimedes-diff.ts` bridge below) |
| `npm:pi-peak-hours` | shows peak-hours indicator in the TUI |
| `npm:pi-bg-bash` | background bash tool with completion wake-up |
| `git:github.com/oglenyaboss/pi-status-anim` | animated status line |
| `npm:pi-commandcode-provider` | optional: provider extension for CommandCode models |

Skip any package already listed in `${PI_DIR}/settings.json -> packages`.

Done when `pi list` shows every chosen package.

## 3. Local extensions

Link the chosen extensions from `<llstack dir>/harnesses/pi/extensions/` into `${PI_DIR}/extensions/`:

| Extension | What it does |
| --- | --- |
| `astra-guidance.ts` | OpenAI/GPT prompt rules: colleague-style writing, removes pi's `Be concise` line, raises Codex `text.verbosity` from `low` to `medium` |
| `archimedes-diff.ts` | bridge that registers `@pi-archimedes/diff` write/edit rendering (required when `npm:@pi-archimedes/diff` is installed) |

If a file with the same name already exists in `${PI_DIR}/extensions/`, show what it is and ask whether to move it to `${PI_DIR}/llstack-backup/` before linking.

Done when `ls -l ${PI_DIR}/extensions/` shows each chosen link resolving into `<llstack dir>/harnesses/pi/extensions/`.

## 4. Settings, MCP and web-search

Compare the user's current files with the examples in this directory and ask which keys to merge:

- [settings.example.json](settings.example.json) -> `${PI_DIR}/settings.json` (TUI mode, `defaultTools`, `retry`, `archimedes.core`, `peakHours`, `statusAnim`). Keep the user's existing `defaultProvider`, `defaultModel`, `enabledModels`, `deviceId` and any other keys intact.
- [mcp.example.json](mcp.example.json) -> `${PI_DIR}/mcp.json` (`context7` and `chrome-devtools`, both `lazy` and `deferred`).
- [web-search.example.json](web-search.example.json) -> `~/.pi/web-search.json` (`auto-summary` workflow; only when `pi-web-access` was installed).

Before editing any JSON file: copy it to `<file>.bak-llstack`, merge into the existing JSON (keep untouched keys, append to arrays without duplicates), then confirm `jq empty <file>` succeeds.

Done when every touched JSON file passes `jq empty` and reads back with the chosen keys.

## 5. Rules and providers

- Global rules from [../../rules/AGENTS.md](../../rules/AGENTS.md) go into `${PI_DIR}/AGENTS.md` (handled by step 6 of the root `INSTALL.md`).
- Provider credentials stay outside llstack: remind the user to run `pi auth` or configure providers in `${PI_DIR}/models.json` if this is a fresh machine.
