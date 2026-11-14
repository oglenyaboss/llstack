#!/usr/bin/env node
/**
 * PR risk tier from the branch diff (see references/review-policy.md).
 *
 *   node <skill dir>/scripts/risk.mjs [--base <ref>] [--config <path>]
 *
 * The "path -> tier" table is .github/risk-tiers.yml in the project root;
 * --config names another table, resolved against the project root.
 * A file is high if it matches high; else low if it matches low; else medium.
 * The PR tier is the maximum over files. The first output line is the tier;
 * then the files that determined it. An empty diff exits 1: "nothing to
 * classify" is not "low risk".
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

const TIERS_FILE = ".github/risk-tiers.yml";
const ORDER = ["low", "medium", "high"];

const USAGE = `usage: node risk.mjs [--base <ref>] [--config <path>]

  --base <ref>     ref to compare the working tree against (default: origin/HEAD)
  --config <path>  tier table; a relative path is read from the project root
                   (default: ${TIERS_FILE})
  --help           print this and exit

Prints the tier (low | medium | high), then the files that set it.
Exit 0 classified, 1 could not classify, 2 usage error.`;

class UsageError extends Error {}

export function loadTiers(text, source = TIERS_FILE) {
  const parsed = parseFiltersYaml(text, source);
  for (const key of Object.keys(parsed)) {
    if (key !== "high" && key !== "low") {
      throw new Error(
        `${source}: tier "${key}" is not supported (only high and low; medium is the default)`,
      );
    }
  }
  return {
    high: (parsed.high ?? []).map(globToRegExp),
    low: (parsed.low ?? []).map(globToRegExp),
  };
}

export function classify(files, tiers) {
  if (files.length === 0)
    throw new Error("empty diff: nothing to classify");
  const grouped = { high: [], medium: [], low: [] };
  for (const file of files) {
    const tier = tiers.high.some((re) => re.test(file))
      ? "high"
      : tiers.low.some((re) => re.test(file))
        ? "low"
        : "medium";
    grouped[tier].push(file);
  }
  const tier = [...ORDER].reverse().find((t) => grouped[t].length > 0);
  return { tier, files: grouped };
}

/**
 * Minimal parser for risk-tiers.yml: a "tier -> list of glob strings" map.
 * No dependencies: plain lists and the empty flow list (`low: []`) are the
 * whole format. Any other YAML shape (nested maps, non-empty flow lists,
 * etc.) is an error (fail-closed) rather than a silently wrong result.
 * A list item may be a plain scalar, a single-quoted scalar (a doubled
 * apostrophe is one apostrophe) or a double-quoted scalar, decoded with
 * JSON.parse, so JSON escapes in it work.
 * A `#` starts a comment only outside a quoted scalar and only after a space.
 */
export function parseFiltersYaml(text, source = TIERS_FILE) {
  const filters = {};
  let current = null;
  for (const rawLine of text.split("\n")) {
    const line = rawLine.replace(/\t/g, "  ");
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const itemMatch = trimmed.match(/^-\s+(.+)$/);
    if (itemMatch) {
      if (!current)
        throw new Error(`${source}: list item outside a tier: ${trimmed}`);
      const value = itemValue(itemMatch[1], source);
      if (!value)
        throw new Error(`${source}: empty pattern in tier ${current}`);
      filters[current].push(value);
      continue;
    }

    const keyMatch = line.match(/^(\S+):(.*)$/);
    if (keyMatch) {
      const rest = keyMatch[2];
      const emptyFlowList = /^\s*\[\s*\]\s*(?:#.*)?$/.test(rest);
      const listIntro = /^\s*(?:#.*)?$/.test(rest);
      if (!emptyFlowList && !listIntro)
        throw new Error(
          `${source}: unsupported line (fail-closed): ${rawLine}`,
        );
      current = keyMatch[1];
      if (filters[current] !== undefined) {
        throw new Error(`${source}: duplicate tier ${current}`);
      }
      filters[current] = [];
      continue;
    }

    throw new Error(`${source}: unsupported line (fail-closed): ${rawLine}`);
  }
  if (Object.keys(filters).length === 0)
    throw new Error(`${source}: no tiers found`);
  return filters;
}

/** Decode one list item; trailing junk, bad escapes and open quotes are errors. */
function itemValue(raw, source) {
  const fail = (message) => new Error(`${source}: ${message}: ${raw}`);
  if (raw[0] === '"') {
    let end = -1;
    for (let i = 1; i < raw.length; i++) {
      if (raw[i] === "\\") {
        i++;
      } else if (raw[i] === '"') {
        end = i;
        break;
      }
    }
    if (end === -1) throw fail("unterminated double-quoted pattern");
    if (!/^\s*(?:#.*)?$/.test(raw.slice(end + 1)))
      throw fail("trailing content after a quoted pattern (fail-closed)");
    const token = raw.slice(0, end + 1);
    try {
      return JSON.parse(token);
    } catch {
      throw new Error(
        `${source}: invalid double-quoted pattern (fail-closed): ${token}`,
      );
    }
  }
  if (raw[0] === "'") {
    let value = "";
    let end = -1;
    for (let i = 1; i < raw.length; i++) {
      if (raw[i] !== "'") {
        value += raw[i];
      } else if (raw[i + 1] === "'") {
        value += "'";
        i++;
      } else {
        end = i;
        break;
      }
    }
    if (end === -1) throw fail("unterminated single-quoted pattern");
    if (!/^\s*(?:#.*)?$/.test(raw.slice(end + 1)))
      throw fail("trailing content after a quoted pattern (fail-closed)");
    return value;
  }
  if (raw[0] === "[" || raw[0] === "{")
    throw fail("unsupported list item (fail-closed)");
  // A plain scalar: # starts a comment only at the start or after whitespace.
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] === "#" && (i === 0 || /\s/.test(raw[i - 1])))
      return raw.slice(0, i).trim();
  }
  return raw.trim();
}

/**
 * Glob -> RegExp (a picomatch subset, enough for risk-tiers.yml):
 * `**` matches any segments, `*` matches inside a segment (no `/`),
 * `?` matches one character except `/`. Inputs are file lists, so edge cases
 * like "the directory is its own match" do not occur. The `s` flag keeps `.`
 * matching a newline: git allows one in a filename, and a High path must not
 * fall through to a lower tier because of it.
 */
export function globToRegExp(glob) {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        while (glob[i + 1] === "*") i++;
        if (glob[i + 1] === "/") {
          re += "(?:.*/)?";
          i++;
        } else {
          re += ".*";
        }
      } else {
        re += "[^/]*";
      }
    } else if (c === "?") {
      re += "[^/]";
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`^${re}$`, "s");
}

/**
 * Files changed between merge-base(HEAD, base) and the working tree.
 * Paths come from `-z` output, so git neither quotes nor escapes them and a
 * unicode, space-bearing or newline-bearing name stays one exact path.
 */
export function changedFiles(base, cwd) {
  const mergeBase = execFileSync("git", ["merge-base", "HEAD", base], {
    cwd,
    encoding: "utf8",
  }).trim();
  return execFileSync("git", ["diff", "--name-only", "-z", mergeBase], {
    cwd,
    encoding: "utf8",
  })
    .split("\0")
    .filter((f) => f !== "");
}

/**
 * Argument parsing: --base=<ref> or --base <ref>, --config=<path> or
 * --config <path>. Anything else is a usage error: a mistyped flag must not
 * fall back to the default base and classify the wrong diff.
 */
export function parseArgs(argv) {
  const options = { base: "origin/HEAD", config: TIERS_FILE, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
      continue;
    }
    const match = arg.match(/^--(base|config)(?:=(.*))?$/);
    if (match) {
      const value = match[2] ?? argv[++i];
      if (!value || value.startsWith("--"))
        throw new UsageError(`--${match[1]} needs a value\n\n${USAGE}`);
      options[match[1]] = value;
      continue;
    }
    throw new UsageError(`unknown argument "${arg}"\n\n${USAGE}`);
  }
  return options;
}

function firstLine(text) {
  return String(text).trim().split("\n").find(Boolean) ?? "";
}

function projectRoot(cwd) {
  try {
    return execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd,
      encoding: "utf8",
    }).trim();
  } catch (error) {
    throw new Error(
      `not inside a git work tree: ${firstLine(error.stderr ?? error.message)}`,
    );
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(USAGE);
    return;
  }
  const cwd = process.cwd();
  const root = projectRoot(cwd);
  const tablePath = isAbsolute(options.config)
    ? options.config
    : join(root, options.config);
  if (!existsSync(tablePath))
    throw new Error(
      `${options.config} not found in ${root}; copy references/risk-tiers.example.yml from the pr-risk skill there`,
    );

  let files;
  try {
    files = changedFiles(options.base, cwd);
  } catch (error) {
    throw new Error(
      `cannot classify against base ${options.base}: ${firstLine(error.stderr ?? error.message)}`,
    );
  }

  const { tier, files: grouped } = classify(
    files,
    loadTiers(readFileSync(tablePath, "utf8"), options.config),
  );
  console.log(tier);
  for (const t of ["high", "medium"]) {
    if (grouped[t].length > 0) console.log(`${t}: ${grouped[t].join(", ")}`);
  }
}

if (realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(
      `risk.mjs: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exit(error instanceof UsageError ? 2 : 1);
  }
}
