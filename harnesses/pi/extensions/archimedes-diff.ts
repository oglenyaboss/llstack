/**
 * Bridge for @pi-archimedes/diff.
 *
 * The published diff package is a library module (named exports only, no
 * default factory), so `pi install npm:@pi-archimedes/diff` fails with
 * "Extension does not export a valid factory function".
 *
 * This wrapper registers its write/edit diff rendering manually.
 * Config is read from ~/.pi/agent/settings.json under "archimedes.diff".
 */
import { readFileSync } from "node:fs";
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { registerDiffTools } from "@pi-archimedes/diff";

const DEFAULTS = {
	diffTheme: "github-dark",
	diffSplitMinWidth: 150,
	diffSplitMinCodeWidth: 60,
};

function loadConfig(): typeof DEFAULTS {
	try {
		const raw = JSON.parse(
			readFileSync(`${process.env.PI_CODING_AGENT_DIR ?? `${process.env.HOME}/.pi/agent`}/settings.json`, "utf8"),
		);
		return { ...DEFAULTS, ...(raw?.["archimedes.diff"] ?? {}) };
	} catch {
		return DEFAULTS;
	}
}

export default function (pi: ExtensionAPI): void {
	// getTheme is unused by the current registerDiffTools implementation
	// (colors are derived at render time from the active pi theme).
	registerDiffTools(pi, () => ({} as Theme), loadConfig);
}
