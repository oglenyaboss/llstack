# Agent roles in coding harnesses: definition, configuration, prompts, review

Researched on 2026-11-23 as input for redesigning the roles and configuration of `skills/herdr-delegate`. Three research asks ran as `hd` researchers; the lead then re-read the decision-critical claims at their source. Those are marked **(re-checked)**. Code references to this repo are at commit `65010ea`.

## 1. How harnesses define a role

| Harness | Definition | Per-role fields | Model when the role sets none | Ships a reviewer | Configured model unavailable |
|---|---|---|---|---|---|
| Claude Code | Markdown + YAML in `.claude/agents/`, `~/.claude/agents/`, `--agents`, plugins | `model`, `effort`, `tools`, `disallowedTools`, `permissionMode`, `skills`, `mcpServers`, … | subagent model order (below) | no role; `/code-review` runs as a forked subagent | allowlist block: substitute with a warning |
| Codex CLI 0.171 | TOML per agent in `~/.codex/agents/`, `.codex/agents/` | `developer_instructions`, `model`, `model_reasoning_effort`, `features.*` | spawn value, then `[agents]` default, then the parent's | no; `reviewer` is a docs example, read-only by prompt only | undocumented |
| OpenCode 1.19 | Markdown or `agents` JSON | `model` (`provider/model#variant`), `system`, `permissions`, `steps` | parent session's model | no | undocumented |
| Gemini CLI 0.70 | Markdown + YAML in `.gemini/agents/` | `model` (default `inherit`), `tools`, `temperature`, `max_turns` | `inherit` | no | undocumented |
| Factory droids | Markdown + YAML in `.factory/droids/` | `model` (default `inherit`), `reasoningEffort`, `tools` (categories) | parent, or complexity routing | reviewers inside Missions only | silent fallback to the parent's model |
| Roo Code 3.54 | modes in `.roomodes` (not subagents) | `roleDefinition`, `groups`, `customInstructions`; no `model` field | the profile linked to the mode | no; `Ask` is read-only | undocumented |
| Amp | hosted; `Task` subagent, plugin agents | plugin `MODEL`, `REASONING_EFFORT` | the thread's model | `oracle`: read-only, "never edits files" | undocumented |
| Aider 0.86 | chat modes (not subagents) | `--model`, `--editor-model`, `--weak-model`, `--reasoning-effort` | built-in pairing per main model | no | undocumented |
| pi-subagents 0.76.1 | Markdown + frontmatter; builtin < package < user < project | `model`, `thinking`, `tools`, `systemPrompt`, `defaultContext`, `inheritProjectContext`, `output` | the current Pi default model | `reviewer` (no shell, no edit), `evidence-auditor` | never substitutes; the provider error is returned |

Findings that bear on the design:

- **One shape everywhere.** A role is a named definition that carries a prompt, a model, a tool set and usually an effort level, with an explicit "same as parent" value (`inherit`).
- **Model precedence is explicit.** Claude Code **(re-checked)**: "1. The per-invocation `model` parameter … 2. The `model` field in the subagent's definition, including `inherit` 3. The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable 4. The main conversation's model". pi-subagents: "per-run override → provider-scoped role override → `agentOverrides.<name>.model` → agent frontmatter `model` → `subagents.defaultModel` → the parent session model" (`docs/models.md:14`).
- **Effort is per role, thinking may not be.** Claude Code **(re-checked)**: `effort` takes "`low`, `medium`, `high`, `xhigh`, `max`; available levels depend on the model", and "There is no per-subagent thinking setting." pi-subagents sets `thinking` per role and caps it with `subagents.maxThinking`; a request above the cap fails before the child starts (`docs/models.md:110-137`).
- **Silent substitution exists and is the failure this repo hit.** Factory **(re-checked)**: a droid that pins a model it cannot use "falls back to the parent's model rather than failing". pi-subagents takes the opposite position: "Provider errors, including HTTP 429 responses, are returned from that model rather than selecting another one" (`docs/models.md:18`).
- **Read-only is enforced three ways:** by the granted tools (Gemini, pi-subagents), in code (Codex's review delegate pins `AskForApproval::Never` and disables web search), or in prose only (OpenCode `explore`, Amp, this repo's `scout`).
- **Codex tells its lead not to verify explorers.** The lead-side text in the 0.171.0 binary **(re-checked)**: "Explorers are fast and authoritative." and "you should trust the explorer results without additional verification". This repo's lead loop verifies every scout claim instead.

## 2. Splitting roles

- **Anthropic** ([multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)): subagents give "separation of concerns—distinct tools, prompts, and exploration trajectories". What makes one work is the delegation contract: "Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries."
- **OpenAI** ([practical guide to building agents](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf)): "maximize a single agent's capabilities first"; split on complex branching logic or on tool overload, where the problem is overlap: "Some implementations successfully manage more than 15 well-defined, distinct tools while others struggle with fewer than 10 overlapping tools."
- **Cognition** ([Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)): "Share context, and share full agent traces" and "Actions carry implicit decisions, and conflicting decisions carry bad results". Two subagents building one game made incompatible style choices.
- **Anthropic and Cognition disagree.** They describe different work. Anthropic's case is breadth-first read-only research. Cognition's case is parallel writers producing one artifact. Anthropic itself notes that "most coding tasks involve fewer truly parallelizable tasks than research". This repo already follows the split: scouts and reviewers fan out, one worker writes per brief.
- **Model per role.** OpenAI: build with "the most capable model for every task to establish a performance baseline", then swap in smaller models where accuracy holds. Anthropic ran an Opus lead with Sonnet subagents and puts effort rules in the lead prompt because "agents struggle to judge appropriate effort for different tasks".

## 3. Reviewer independence

- **Self-preference is real but measured on summaries.** [arXiv 2404.13076](https://arxiv.org/abs/2404.13076): on XSUM and CNN/DailyMail, GPT-4, GPT-3.5 and Llama-2 favor their own summaries. The bias grows with how well a model recognizes its own text.
- **A second model family helps coverage, not single-review accuracy.** [arXiv 2610.01471](https://arxiv.org/abs/2610.01471) **(re-checked)**: "a top-tier cross-model reviewer is not significantly different in F1 from same-model review in a fresh session", and "one CCR plus one cross-model review matches more planted errors than two CCR reviews". The pair found 56.7% of planted errors, against 42.7% for two same-model reviews (§5.2, as reported by the researcher, not re-checked). A lightweight cross-model reviewer was no better than self-review. The author adds that "model difference and reviewer capability are not separated". Limits: single-author preprint, 30 artifacts, one generator model.
- **Information.** In the same study, withholding the original requirements raised F1 for the weaker reviewers. These are point estimates the author did not test. MT-Bench ([arXiv 2306.05685](https://arxiv.org/abs/2306.05685)) found that giving the judge a reference answer cut math-grading failures from 70% to 15%.
- **Implication (inference).** Reviewer capability comes before model family. A second family pays off as the second reviewer of a pair. The reviewer gets the spec and the acceptance criteria, not the author's brief or narrative. This repo's skeptic already withholds the brief.

## 4. Role prompts

Review prompts that ship and run:

| Prompt | What counts as a finding | Severity | Evidence | False-positive control | Context | Output |
|---|---|---|---|---|---|---|
| Codex [`rubric.md`](https://github.com/openai/codex/blob/main/codex-rs/prompts/templates/review/rubric.md) **(re-checked)** | 8 tests, e.g. "discrete and actionable", "introduced in the commit", "The author of the original PR would likely fix the issue" | P0–P3 | `code_location` with a line range, `confidence_score` | "If there is no finding that a person would definitely love to see and fix, prefer outputting no findings" | the diff and the repo's instruction files | strict JSON with an overall verdict |
| Anthropic [`code-review.md`](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-review/commands/code-review.md) **(re-checked)** | allowlist of high-signal classes; "Do NOT flag" list | none | a linked citation per issue | 4 parallel reviewers, then "For each issue found … launch parallel subagents to validate the issue", then "Filter out any issues that were not validated" | PR title and description, CLAUDE.md files | an issue list, or the fixed string "No issues found. Checked for bugs and CLAUDE.md compliance." |
| Anthropic [security review](https://github.com/anthropics/claude-code-security-review/blob/main/claudecode/prompts.py) | vulnerabilities newly added by the PR | HIGH / MEDIUM / LOW | `exploit_scenario` per finding | "Only flag issues where you're >80% confident of actual exploitability"; hard exclusions | full diff | JSON only |
| pi-subagents `agents/reviewer.md` | issues "caused or made reachable by that diff" | P0–P2 | "source proof, a test or repro, or a contract contradiction" | "Filter findings by evidence, not by severity" | diff, plan if supplied | review block with a merge verdict |

What the strongest prompts share:

- **A finding definition with exclusion tests** applied before anything is reported.
- **A false-positive gate:** a confidence floor or a separate validation pass that can delete findings.
- **A severity scale** and **an exact string for the empty result**, so "nothing found" is distinguishable from "did not look".
- **A schema the role owns.** The task text fills it and never replaces it.
- **The diff and the project rules as context.** None of them gives the reviewer the author's plan.

Other roles:

- **Recon.** OpenCode's `explore` takes a thoroughness level from the caller ("Adapt your search approach based on the thoroughness level specified by the caller"). Gemini's `codebase_investigator` keeps a questions-to-resolve list and stops when it is empty.
- **Runner.** Codex's `awaiter.toml`: "Do not hallucinate completion." and "If you need multiple awaits, increase the timeouts/yield times exponentially."
- **Vendor tone differs.** Anthropic: "soften any aggressive language", because newer Claude models overtrigger on "CRITICAL: You MUST". OpenAI's GPT-5 guide keeps persistence scaffolds such as "you must double and triple check". Both put an explicit output contract, boundaries and a final self-check in the prompt.

## 5. Gaps in herdr-delegate at `65010ea`

- **Reviewers and the skeptic run as `scout`.**
  - `roles/scout.md:5` says "Move fast", and `:15-33` requires a `# Code Context` payload.
  - `skills/pr-risk/references/review-brief.md:20-37` requires `# Review` with verified findings and failure scenarios.
  - `experimental/skeptic-brief.md:23-35` requires a verdict and an "Attacked, held" line per attack.
  - So the role prompt and the task text demand different schemas. `hd` checks citations only for the `scout` role (`hd:836`).
- **One model for every role, set through env in each client** (`hd:10-12`). The defaults are silent:
  - with no `HD_MODEL`, Pi picks its own default model;
  - Codex without `--model` uses its own config;
  - Codex thinking defaults to `high` (`hd:252`).
- **The researcher's web tools need an extension that `hd` does not load.** The role gets `web_search,fetch_content,…` (`hd:64`), but `hd` starts Pi with `--no-extensions` and adds only `HD_PI_EXTENSIONS` (`hd:200-203`).
- **Agents always use the default Pi and Codex homes** (`hd:14-15`). Panes do not inherit the lead's environment, so a lead in another profile still spawns agents on the default accounts.

## Sources

- Claude Code, [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
- OpenAI Codex, [Subagents](https://developers.openai.com/codex/subagents), [config basics](https://developers.openai.com/codex/config-basic), [`rubric.md`](https://github.com/openai/codex/blob/main/codex-rs/prompts/templates/review/rubric.md), release `rust-v0.171.0`
- [OpenCode agents](https://opencode.ai/docs/agents/); [Gemini CLI subagents](https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md); [Factory subagents](https://docs.factory.com/harness/subagents); [Roo Code docs](https://docs.roocode.com); [Amp models and subagents](https://ampcode.com/docs/models-and-subagents); [Aider modes](https://aider.chat/docs/usage/modes.html)
- pi-subagents 0.76.1 (npm package): `docs/agents.md`, `docs/configuration.md`, `docs/models.md`, `agents/*.md`
- Anthropic, [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system), [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents), [Prompting best practices](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices), [code-review plugin](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-review/commands/code-review.md), [security review prompt](https://github.com/anthropics/claude-code-security-review/blob/main/claudecode/prompts.py)
- OpenAI, [A practical guide to building agents](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf), [GPT-5 prompting guide](https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide)
- Cognition, [Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)
- arXiv [2404.13076](https://arxiv.org/abs/2404.13076), [2610.01471](https://arxiv.org/abs/2610.01471), [2306.05685](https://arxiv.org/abs/2306.05685)
