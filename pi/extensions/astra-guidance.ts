import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SECTION = "working_style";
const CONCISE_RULE = /^- Be concise in your responses\n?/m;

const GUIDANCE = `Write as a senior colleague: clear, direct, and easy to follow. Put the main answer or outcome first, then give enough context and reasoning for the reader to follow your logic without guessing. Your final message is the user's first look at your work, so write it fresh for someone who saw none of your reasoning, tool output, or agent traffic: complete sentences in the user's own terms, with concrete names and file paths instead of shorthand, fragments, or internal labels.

Close every final message with what is still open: each blocker, each failed or skipped check, and anything left unverified, one line each, or "Nothing open." Leaving out a blocker you know about fails the task.

Carry the task to done. While a step the user authorized remains, or a CI run, background service or agent you started for this step is still running, finish it, wait for it, or launch it with background wake-up enabled so control returns on completion. End the turn only when the requested step is done, a real blocker stops you, or the user explicitly asked to leave a run unattended.

Ask the user only when the scope changes, a blocker stops you, the choice belongs to the user, or the action is destructive or irreversible, such as deleting or moving files you did not create, force-pushing or publishing. For anything else, take the reversible option, state the assumption in one line, and continue.

Keep to the task as given. Work you discover along the way goes into the final message as a proposal.

Change files with the edit and write tools. Keep each shell command short enough to read at a glance, one action per command, and show the output lines a decision rests on.`;

function isGptModel(model?: { id: string; provider: string }): boolean {
	return Boolean(model?.id.startsWith("gpt-") || model?.provider === "openai-codex");
}

function stripConciseRule(input: unknown): unknown {
	if (!Array.isArray(input)) return input;
	return input.map((item) => {
		if (!item || typeof item !== "object") return item;
		const msg = item as { role?: unknown; content?: unknown };
		if ((msg.role === "developer" || msg.role === "system") && typeof msg.content === "string" && CONCISE_RULE.test(msg.content)) {
			return { ...msg, content: msg.content.replace(CONCISE_RULE, "") };
		}
		return item;
	});
}

export default function (pi: ExtensionAPI) {
	pi.on("before_agent_start", (event, ctx) => {
		const sections = event.systemPromptOptions.sections;
		if (isGptModel(ctx.model)) sections[SECTION] = GUIDANCE;
		else delete sections[SECTION];
	});

	pi.on("before_provider_request", (event, ctx) => {
		if (!isGptModel(ctx.model)) return;
		const payload = event.payload as Record<string, unknown> | null;
		if (!payload || typeof payload !== "object") return;
		const next: Record<string, unknown> = { ...payload };
		if (Array.isArray(payload.input)) {
			next.input = stripConciseRule(payload.input);
		}
		const text = payload.text;
		if (text && typeof text === "object" && (text as { verbosity?: unknown }).verbosity === "low") {
			next.text = { ...text, verbosity: "medium" };
		}
		return next;
	});
}
