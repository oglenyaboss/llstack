import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  changedFiles,
  classify,
  globToRegExp,
  loadTiers,
  parseFiltersYaml,
} from "../scripts/risk.mjs";

const SCRIPT = fileURLToPath(new URL("../scripts/risk.mjs", import.meta.url));

const FIXTURE = `high:
  - "apps/shared/**"
  - "apps/webhook/**"
  - "src/tools/propose-live-change*"
low:
  - "docs/**"
  - "**/*.md"
  - "apps/ui/public/**"
  - "**/*.spec.ts"
`;

const tiers = loadTiers(FIXTURE);

const GIT_ENV = {
  ...process.env,
  GIT_AUTHOR_NAME: "risk test",
  GIT_AUTHOR_EMAIL: "risk@example.com",
  GIT_COMMITTER_NAME: "risk test",
  GIT_COMMITTER_EMAIL: "risk@example.com",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
};

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8", env: GIT_ENV });
}

function tempRepo(t) {
  const dir = mkdtempSync(join(tmpdir(), "risk-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  git(dir, "init", "-q", "-b", "main");
  return dir;
}

function commitFile(repo, name, content, message) {
  mkdirSync(join(repo, name, ".."), { recursive: true });
  writeFileSync(join(repo, name), content);
  git(repo, "add", name);
  git(repo, "commit", "-q", "-m", message);
}

/** A file in the working tree that git reports in the diff (intent-to-add). */
function writeWorkingFile(repo, name, content = "x\n") {
  const abs = join(repo, name);
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, content);
  git(repo, "add", "-N", "--", name);
}

const PATH_TABLE = 'high:\n  - "src/auth/**"\nlow:\n  - "**/*.md"\n';

function pathTiers() {
  return loadTiers(PATH_TABLE);
}

function repoWithBranchDiff(t) {
  const repo = tempRepo(t);
  commitFile(repo, "a.txt", "a\n", "a");
  git(repo, "checkout", "-q", "-b", "f");
  commitFile(repo, "b.txt", "b\n", "b");
  return repo;
}

function runCli(args, cwd, extra = {}) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...GIT_ENV, ...extra },
  });
}

function repoWithCustomTable(t) {
  const repo = tempRepo(t);
  commitFile(repo, "core/x.txt", "x\n", "x");
  git(repo, "checkout", "-q", "-b", "f");
  commitFile(repo, "core/y.txt", "y\n", "y");
  mkdirSync(join(repo, "config"), { recursive: true });
  writeFileSync(
    join(repo, "config/tiers.yml"),
    'high:\n  - "core/**"\nlow:\n  - "docs/**"\n',
  );
  return repo;
}

test("A1: ui public assets and docs -> low", () => {
  assert.equal(
    classify(["apps/ui/public/x.svg", "docs/a.md"], tiers).tier,
    "low",
  );
});

test("A2: ui logic outside the lists -> medium", () => {
  const r = classify(["apps/ui/src/Page.tsx"], tiers);
  assert.equal(r.tier, "medium");
  assert.deepEqual(r.files.medium, ["apps/ui/src/Page.tsx"]);
});

test("A3: one high file raises the whole PR to high", () => {
  const r = classify(["apps/ui/src/a.tsx", "apps/shared/k.ts"], tiers);
  assert.equal(r.tier, "high");
  assert.deepEqual(r.files.high, ["apps/shared/k.ts"]);
});

test("A4: a spec inside the high zone stays high", () => {
  assert.equal(
    classify(["apps/webhook/src/a.spec.ts"], tiers).tier,
    "high",
  );
});

test("A5: a spec outside the high zone -> low", () => {
  assert.equal(classify(["apps/admin/members.spec.ts"], tiers).tier, "low");
});

test("A6: live-change tools -> high", () => {
  assert.equal(
    classify(["src/tools/propose-live-change.tool.ts"], tiers).tier,
    "high",
  );
});

test("A7: **/*.md matches a root file", () => {
  assert.equal(classify(["README.md"], tiers).tier, "low");
});

test("A8: empty diff is an error, not low", () => {
  assert.throws(() => classify([], tiers), /empty diff: nothing to classify/);
});

test("A9: a tier outside high/low is an error", () => {
  assert.throws(
    () => loadTiers('medium:\n  - "apps/**"\n'),
    /tier "medium" is not supported/,
  );
});

test("A10: duplicate tier key", () => {
  assert.throws(
    () => parseFiltersYaml("high:\n  - a\nhigh:\n  - b\n", "t.yml"),
    { message: "t.yml: duplicate tier high" },
  );
});

test("A11: list item outside a tier", () => {
  assert.throws(() => parseFiltersYaml("  - a\n", "t.yml"), {
    message: "t.yml: list item outside a tier: - a",
  });
});

test("A12: * does not cross /", () => {
  assert.equal(globToRegExp("apps/*.ts").test("apps/x/y.ts"), false);
  assert.equal(globToRegExp("apps/*.ts").test("apps/a.ts"), true);
});

test("A13: changedFiles compares merge-base with the working tree", (t) => {
  const repo = repoWithBranchDiff(t);
  writeFileSync(join(repo, "a.txt"), "a modified\n");
  assert.deepEqual(changedFiles("main", repo), ["a.txt", "b.txt"]);
});

test("A14: the CLI roots the default table at the project, not the cwd", (t) => {
  const repo = repoWithBranchDiff(t);
  mkdirSync(join(repo, ".github"), { recursive: true });
  writeFileSync(join(repo, ".github/risk-tiers.yml"), FIXTURE);
  mkdirSync(join(repo, "nested"));
  const result = runCli(["--base", "main"], join(repo, "nested"));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[0], "medium");
});

test("A15: the CLI runs through a symlinked skill directory", (t) => {
  const repo = repoWithBranchDiff(t);
  mkdirSync(join(repo, ".github"), { recursive: true });
  writeFileSync(join(repo, ".github/risk-tiers.yml"), FIXTURE);
  const link = join(mkdtempSync(join(tmpdir(), "risk-link-")), "pr-risk");
  t.after(() => rmSync(dirname(link), { recursive: true, force: true }));
  symlinkSync(dirname(dirname(SCRIPT)), link);
  const result = spawnSync(
    process.execPath,
    [join(link, "scripts/risk.mjs"), "--base", "main"],
    { cwd: repo, encoding: "utf8", env: GIT_ENV },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[0], "medium");
});

test("B1: --config takes another table, rooted at the project", (t) => {
  const repo = repoWithCustomTable(t);
  mkdirSync(join(repo, "nested"), { recursive: true });
  const result = runCli(
    ["--base", "main", "--config", "config/tiers.yml"],
    join(repo, "nested"),
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "high\nhigh: core/y.txt\n");
});

test("B2: --config accepts an absolute path", (t) => {
  const repo = repoWithCustomTable(t);
  const table = join(repo, "config/tiers.yml");
  const result = runCli(["--base", "main", `--config=${table}`], repo);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[0], "high");
});

test("B3: a missing --config file is an error naming the path", (t) => {
  const repo = repoWithCustomTable(t);
  const result = runCli(
    ["--base", "main", "--config", "config/missing.yml"],
    repo,
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /risk\.mjs: /);
  assert.match(result.stderr, /config\/missing\.yml/);
  assert.equal(result.stdout, "");
});

test("B4: an unknown argument is a usage error, not a silent default", (t) => {
  const repo = repoWithCustomTable(t);
  const result = runCli(["--bse", "main"], repo);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /usage/);
  assert.equal(result.stdout, "");
});

test("B5: --base with no value is a usage error", (t) => {
  const repo = repoWithCustomTable(t);
  const result = runCli(["--base"], repo);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /usage/);
});

test("B6: a base that does not resolve names the base", (t) => {
  const repo = repoWithCustomTable(t);
  mkdirSync(join(repo, ".github"), { recursive: true });
  writeFileSync(join(repo, ".github/risk-tiers.yml"), FIXTURE);
  const result = runCli(["--base", "nope"], repo);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /cannot classify against base nope/);
  assert.equal(result.stdout, "");
});

test("B7: --help prints usage and exits 0", (t) => {
  const repo = repoWithCustomTable(t);
  const result = runCli(["--help"], repo);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /--base <ref>/);
  assert.match(result.stdout, /--config <path>/);
});

test("B8: a malformed table names the table it read", (t) => {
  const repo = repoWithCustomTable(t);
  writeFileSync(join(repo, "config/broken.yml"), "core:\n  - a\n");
  const result = runCli(
    ["--base", "main", "--config", "config/broken.yml"],
    repo,
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /config\/broken\.yml/);
});

test("C1: an empty flow list is an empty tier", () => {
  assert.deepEqual(parseFiltersYaml('high:\n  - "src/**"\nlow: []\n', "t.yml"), {
    high: ["src/**"],
    low: [],
  });
  assert.deepEqual(parseFiltersYaml("high:\n  - src/**\nlow: [ ]\n", "t.yml"), {
    high: ["src/**"],
    low: [],
  });
  assert.deepEqual(
    parseFiltersYaml('high:\n  - "src/**"\nlow: [] # no low paths\n', "t.yml"),
    { high: ["src/**"], low: [] },
  );

  const table = loadTiers('high:\n  - "src/**"\nlow: []\n');
  assert.equal(classify(["src/a.ts"], table).tier, "high");
  assert.equal(classify(["docs/a.md"], table).tier, "medium");
});

test("C2: a non-empty flow list is unsupported, not a smaller table", () => {
  assert.throws(() => parseFiltersYaml('low: ["docs/**"]\n', "t.yml"), {
    message: /t\.yml: unsupported line \(fail-closed\)/,
  });
  assert.throws(() => parseFiltersYaml("low: [docs/**]\n", "t.yml"), {
    message: /t\.yml: unsupported line \(fail-closed\)/,
  });
  assert.throws(() => parseFiltersYaml('low: ["a", "b"]\n', "t.yml"), {
    message: /t\.yml: unsupported line \(fail-closed\)/,
  });
  assert.throws(() => parseFiltersYaml('high:\n  - "src/**"\n  - [a]\n', "t.yml"), {
    message: /t\.yml: .*fail-closed/,
  });
});

test("C3: JSON escapes decode to their characters", () => {
  const text =
    'high:\n  - "src/\\u0444\\u0430\\u0439\\u043b/**"\n  - "src/\\ud83d\\ude00/**"\n';
  assert.deepEqual(parseFiltersYaml(text, "t.yml"), {
    high: ["src/файл/**", "src/😀/**"],
  });
});

test("C4: # inside a quoted glob is content, not a comment", () => {
  const table = loadTiers(
    'high:\n  - "src/a #b/**"\nlow:\n  - "docs/**" # trailing comment\n',
  );
  assert.equal(classify(["src/a #b/x.ts"], table).tier, "high");
  assert.equal(classify(["docs/a.md"], table).tier, "low");
  assert.equal(classify(["src/a/x.ts"], table).tier, "medium");
});

test("C5: an unquoted # comments only after whitespace", () => {
  assert.deepEqual(parseFiltersYaml("high:\n  - src/a#b/**\n", "t.yml"), {
    high: ["src/a#b/**"],
  });
  assert.deepEqual(parseFiltersYaml("high:\n  - src/a/** # note\n", "t.yml"), {
    high: ["src/a/**"],
  });
});

test("C6: a single-quoted glob keeps a doubled apostrophe", () => {
  assert.deepEqual(parseFiltersYaml("high:\n  - 'src/it''s/**'\n", "t.yml"), {
    high: ["src/it's/**"],
  });
  assert.deepEqual(parseFiltersYaml("high:\n  - 'src/a #b/**'\n", "t.yml"), {
    high: ["src/a #b/**"],
  });
});

test("C7: malformed or ambiguous quoted patterns fail closed", () => {
  assert.throws(() => parseFiltersYaml('high:\n  - "src/\\q/**"\n', "t.yml"), {
    message: /t\.yml: .*fail-closed/,
  });
  assert.throws(() => parseFiltersYaml('high:\n  - "src/oops/**\n', "t.yml"), {
    message: /t\.yml: .*unterminated/,
  });
  assert.throws(() => parseFiltersYaml("high:\n  - 'src/oops/**\n", "t.yml"), {
    message: /t\.yml: .*unterminated/,
  });
  assert.throws(() => parseFiltersYaml('high:\n  - "a" "b"\n', "t.yml"), {
    message: /t\.yml: .*fail-closed/,
  });
  assert.throws(() => parseFiltersYaml("high:\n  - 'a' junk\n", "t.yml"), {
    message: /t\.yml: .*fail-closed/,
  });
});

test("D1: changedFiles keeps unicode and inner spaces, so high holds", (t) => {
  const repo = repoWithBranchDiff(t);
  const name = "src/auth/файл с пробелом.md";
  writeWorkingFile(repo, name);
  const files = changedFiles("main", repo);
  assert.ok(files.includes(name), JSON.stringify(files));
  assert.equal(classify(files, pathTiers()).tier, "high");
});

test("D2: changedFiles keeps a newline in a filename, so high holds", (t) => {
  const repo = repoWithBranchDiff(t);
  const name = "src/auth/line\nbreak.md";
  writeWorkingFile(repo, name);
  const files = changedFiles("main", repo);
  assert.ok(files.includes(name), JSON.stringify(files));
  assert.equal(classify(files, pathTiers()).tier, "high");
});

test("D3: changedFiles does not trim edge spaces from a filename", (t) => {
  const repo = repoWithBranchDiff(t);
  const name = " src/auth/edge .md ";
  writeWorkingFile(repo, name);
  const files = changedFiles("main", repo);
  assert.ok(files.includes(name), JSON.stringify(files));
  assert.equal(files.includes(name.trim()), false, JSON.stringify(files));
  const table = loadTiers('high:\n  - " src/auth/edge .md "\n');
  assert.equal(classify(files, table).tier, "high");
});

test("D4: the CLI reports high for a unicode newline path", (t) => {
  const repo = repoWithBranchDiff(t);
  mkdirSync(join(repo, ".github"), { recursive: true });
  writeFileSync(join(repo, ".github/risk-tiers.yml"), PATH_TABLE);
  writeWorkingFile(repo, "src/auth/строка\nпереноса.md");
  const result = runCli(["--base", "main"], repo);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[0], "high");
});
