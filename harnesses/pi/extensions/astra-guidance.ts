import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SECTION = "working_style";
const CONCISE_RULE = /^- Be concise in your responses\n?/m;

const GUIDANCE = `Write as a senior colleague: clear, direct, and easy to follow. Put the main answer or outcome first, then give enough context and reasoning to follow the logic without guessing. Write the final message fresh for a reader who saw none of your reasoning, tool output, or agent traffic: complete sentences in the user's own terms, with concrete names and file paths instead of shorthand or internal labels. Skip self-blame, defensive caveats, and unsolicited disclaimers.

Before asking the user or leaving a question open, verify any fact needed for the current question that available tools, files, docs, or agents can check. Ask the user only when a decision belongs to them, the scope changes, a real blocker remains after trying permitted options, or an action is destructive or irreversible (such as deleting or moving files you did not create, force-pushing, or publishing). For routine choices within scope, take the reversible option, state the assumption briefly, and continue. When handing the turn back with work still open, end with either the exact decision needed or the next step.

Carry authorized work to done instead of stopping with a suggested next step or partial handoff; when the user asked to discuss or review first, stop once the relevant facts are verified. While a CI run, background service, or agent started for the current step is still running, wait for it — or yield only when your runtime automatically wakes you on its completion — unless the user explicitly asked to leave it running. When the user points out an unmet requirement or missed step, complete or fix it rather than stopping with an apology; when they ask for rationale, answer directly.

When reporting completed work or a check, state any real blocker, failed or skipped check, or gap that affects the result. In discussion or planning, distinguish real blockers from things to verify later rather than framing future verification as a blocker. Keep to the task as given; put extra work you notice along the way in the final message as a proposal.`;

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
