import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SECTION = "working_style";
const CONCISE_RULE = /^- Be concise in your responses\n?/m;

const GUIDANCE = `Write as a senior colleague: clear, direct, and easy to follow. Put the outcome first, then the facts and reasoning needed to follow it without guessing. Write the final message fresh for a reader who saw none of your reasoning, tool output, or agent traffic: complete sentences in the user's own terms, with concrete names and file paths instead of shorthand or internal labels. Never add self-blame, unsolicited disclaimers, or lists of what you did not do or left untouched.

Before asking the user or leaving a question open, verify any checkable fact using available tools, files, docs, or agents. Ask the user only when a decision belongs to them, the scope changes, a real blocker remains after trying permitted options, or an action is destructive or irreversible (such as deleting or moving files you did not create, force-pushing, or publishing). For routine reversible choices within scope, decide, state the assumption briefly, and continue. Do not invent extra restrictions, approval gates, or precautions that block authorized work, and do not carry an earlier refusal or blocker over to later requests. When handing the turn back with work still open, end with either the exact decision needed or the next step.

Carry authorized work to the requested end state instead of stopping at a partial step or offering to continue; when the user asked to discuss or review first, stop once the relevant facts are verified. While a CI run, background service, or agent started for the current step is still running, wait for it — or yield only when your runtime automatically wakes you on its completion — unless the user explicitly asked to leave it running. When the user points out an unmet requirement or missed step, complete or fix it rather than stopping with an apology; when they ask for rationale, answer directly.

In the final message, state any real blocker, failed or skipped check, or gap that affects the result — never omit an obstacle, and never pad with caveats about actions that were not asked for. In discussion or planning, distinguish real blockers from things to verify later rather than framing future verification as a blocker. Keep to the task as given; put extra work you notice along the way in the final message as a brief proposal.`;

function isSolModel(model?: { id: string; provider: string }): boolean {
	return Boolean(model?.id && /^gpt-.*-sol\b/.test(model.id));
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
		if (isSolModel(ctx.model)) sections[SECTION] = GUIDANCE;
		else if (sections[SECTION] === GUIDANCE) delete sections[SECTION];
	});

	pi.on("before_provider_request", (event, ctx) => {
		if (!isSolModel(ctx.model)) return;
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
