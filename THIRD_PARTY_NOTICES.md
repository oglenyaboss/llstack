# Third-party notices

Original llstack additions are Copyright (c) 2026 Lenya Lozhkin, MIT. The repository also adapts MIT-licensed text and conventions from the sources below. Their copyright and permission notices are retained in full; modification does not transfer their authorship to llstack.

| Material | Source | Copyright and license |
| --- | --- | --- |
| Setup exploration/confirmation structure, issue-tracker conventions, canonical triage-role vocabulary and parts of the engineering workflow | [mattpocock/skills](https://github.com/mattpocock/skills), reviewed at `5863806dd4e15c63174bee4e7515a4256792ecfa` | Copyright (c) 2026 Matt Pocock; [MIT](licenses/Matt-Pocock-MIT.txt) |
| Adapted scout/worker/researcher role prompts and Code Context payload convention, through the author's herdr-delegate | [nicobailon/pi-subagents](https://github.com/nicobailon/pi-subagents) | Copyright (c) 2026 Nico Bailon; [MIT](licenses/Nico-Bailon-MIT.txt) |
| Deliberate-shortcut annotation convention used by the source driver | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | Copyright (c) 2026 DietrichGebert; [MIT](licenses/DietrichGebert-MIT.txt) |

The role prompts have been adapted for visible executors, explicit acceptance cases and file handoffs. Matt Pocock-derived workflow adds fact validation at the current base SHA, owner decisions and expected-risk handoff. These are adaptations, not endorsements by upstream authors.

## Dependencies and ideas, not bundled source

- [Herdr TUI](https://herdr.dev/tui): external workspace/pane/agent CLI used by `hd`. The newer `hc`/herdr-core app is a different API and is not a drop-in replacement tested by this package. Generated integrations are installed by Herdr and are not relabeled as llstack code.
- [pi](https://github.com/earendil-works/pi): external executor; its core and provider code are not bundled.
- [Claude Code](https://code.claude.com/docs): external client; no proprietary client source is included.
- [OpenAI harness engineering](https://openai.com/index/harness-engineering/): informed executable checks, journals and independent review. Cited as a conceptual source, not a bundled code license.

Retain these notices when redistributing substantial adapted portions. Before adding a new copied component, record its source revision and license here and include any required upstream notice. A README link alone is not a replacement for a required license notice.
