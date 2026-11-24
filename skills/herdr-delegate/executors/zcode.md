# ZCode executor

ZCode runs every role (sidekick, worker, scout, reviewer, researcher) in one persistent interactive TUI inside its Herdr pane; `hd` sends each brief to that pane and reads the reply from ZCode's hooks. Select ZCode with `"harness": "zcode"` in a slot or the `default` of hd's config, or with `--agent zcode`.

Tested with the official CLI **0.17.1** at [fec9759](https://github.com/zai-org/ZCode/commit/fec975905a2abd4c07e35c40d51fa097a2258ec9) and Herdr 0.9.5 on Linux ARM64, using a local test API, DeepSeek V4.1 Flash through OpenCode Go, and DeepSeek V4.1 Flash through Command Code (`openai-chat-completions` at `https://api.commandcode.ai/provider/v1`). Live `hd` runs covered worker and scout spawn, ask with Check and Scope, follow-up asks, and stop and resume with the conversation kept; permission dialogs, failure retries, and timeouts were exercised against the TUI and the test suite. Other platforms and CLI versions are unverified.

## Check the CLI

```sh
command -v zcode
zcode --version
zcode doctor --json
```

`hd` resolves `zcode` once from `PATH` at spawn, so the build must leave an executable named `zcode` on `PATH`. The agent runs with a private `HOME`, so a wrapper script must use absolute paths, not `$HOME` or a version manager shim. The CLI is a workspace package of the official repository, so build or install it from there:

- [README: setup and CLI distribution](https://github.com/zai-org/ZCode/blob/main/README.en.md#zcode-cli-distribution)
- [CLI quickstart: source build and doctor](https://github.com/zai-org/ZCode/blob/main/apps/zcode-cli/docs/usage/01-quickstart.md) (Chinese)

At the tested commit the repository release is v3.18.2 while the CLI prints `0.17.1`; compare `zcode --version`, not the repository version. `doctor` checks the runtime, not model credentials or tool calls. Herdr has no ZCode integration to install; the hooks in its private profile report the agent state to Herdr.

The tested source bundle runs under Node 24.14.0. Keep its adjacent runtime files and workspace dependencies; copying `zcode.cjs` alone is insufficient. Use the pinned Node version for the launcher as well as the build.

## Choose the provider file

`hd` reads one personal provider file and copies it into the agent's private profile. The source file stays untouched.

```sh
personal="${ZCODE_PERSONAL_PROVIDER_CONFIG_FILE:-${ZCODE_DATA_BASE_DIR:-$HOME}/.zcode/v2/provider_config.json}"
jq '{providerId: .config.defaultModelSelection.providerId, modelId: .config.defaultModelSelection.modelId}' "$personal"
```

The model comes from the slot in hd's config; `hd` copies the whole provider file, including its API key. `ZCODE_PERSONAL_PROVIDER_CONFIG_FILE` overrides the source path. Keep keys in that file only: do not put them in hd's config, examples, or a brief. A failed spawn names the missing path or model, never the file's contents.

The selected provider rule must explicitly contain `config.access.type: "api-key"`, a non-empty `apiKey`, and `config.api.baseUrl`. Template-only endpoints and account credentials are not resolved by `hd`.

A slot's `model` and `--model` use `providerId/modelId`; `hd` splits at the first `/` and the rest is the model ID. A slot's `thinking` and `--thinking` set that model's `reasoningLevel`: use a level the model supports, or leave `thinking` out of both the slot and `default`. A model other than the file's `defaultModelSelection` without `thinking` drops the previous model's reasoning level. Spawn fails when the slot has no model.

Provider headers in `config.api.headers` are copied as well. OpenCode Go requires a stable `x-opencode-session` header; configure it with the gateway endpoint described in [OpenCode's harness setup](https://opencode.ai/docs/console/harnesses/).

## Run

```sh
# ~/.config/hd/config.json: {"default": {"harness": "zcode", "model": "example/example-model"}}
# add "thinking": "high" only for a model that supports it

hd spawn w1 worker --cwd ~/src/project
hd ask w1 @brief.md
hd wait w1                    # only after STATUS: still_working
hd result w1
hd peek w1
hd stop w1
hd resume w1
```

`spawn` checks `zcode`, the provider file, the model, and the role before it creates a pane. It starts the TUI with `--cwd`, `--mode yolo`, `--workflow-mode disabled`, and `--locale en-US` in a private profile, then waits for the TUI's prompt before printing `spawned ... agent=zcode`; a startup failure shows the pane tail.

`ask` writes the brief and its `OUTPUT_FILE` footer to a private request file, then submits one line naming that file to the pane. `wait` settles only on the hooks and structured turn log for that request's turn; a timeout returns `STATUS: still_working` and leaves the TUI running for `hd wait`. `result` prints the full `Stop` reply; `peek` shows the pane. Check, Scope, diff, and journal entries keep the same behavior as for pi.

The pane is a normal persistent ZCode TUI. Use it by hand between asks, with `/` commands and its own keyboard; a manual turn is not an `hd` ask and cannot settle `hd wait`. Type between asks; during an ask `hd` owns the pane.

`stop` closes the pane. `resume` reopens the same private profile and session with the saved model, thinking, and cwd; stopping before the first ask resumes a fresh TUI. ZCode restores a persisted session's own model selection, so `hd resume` rejects different model or thinking overrides; change them in the TUI with `/model`. Herdr's server restore is not promised for ZCode; use `hd resume`.

`resume` also recovers a conversation started manually in that TUI. Running `spawn` again with the same stopped name resets its private profile and starts a new conversation.

## Limits

- **Private profile.** Each agent gets its own `HOME`, `USERPROFILE`, `ZCODE_DATA_BASE_DIR`, session DB, logs, and runtime config under `${XDG_CACHE_HOME:-$HOME/.cache}/herdr-delegate`. User-home tools, plugins, skills, MCP servers, credentials, and caches are not inherited. `hd` enables only its own user hooks; it does not write project config, ask for project hook trust, or change your global ZCode config.
- **API keys only.** `hd` supports API-key personal providers copied from the file above. An account login or OAuth credentials are not migrated into the private profile; use pi when the task needs that account.
- **Read-only is an instruction.** A scout loses `Edit` and `ApplyPatch`; a researcher also loses `Bash`. Those are not a security sandbox; `--mode yolo` grants broad tool permissions.
- **Context size is unknown.** `hd` has no ZCode token source; `hd ls` leaves `ctx=` empty rather than inventing a number.
- **Sessions stay with the agent.** `hd resume` restores this agent's private profile and stored session; `--session` applies only to that stored hook log, and cross-agent session import is not supported.
- **Version-sensitive signals.** Turn completion and provider failures arrive in ZCode's JSONL turn log (`turn.completed` / `turn.failed`), verified on CLI 0.17.1. `hd` retries a failed turn once, then returns `STATUS: provider_error`; a cancelled turn returns `STATUS: cancelled` without a retry, and a completed turn without a full `Stop.responseText` returns `STATUS: no_reply`. The failure names a diagnostics path, not the raw log or API response. Re-check these paths after a CLI upgrade.
