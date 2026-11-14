#!/usr/bin/env node
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const USAGE = `node style-diff.mjs <spec.json>   (run from the project dir: Playwright loads from its node_modules)

spec.json:
{
  "viewport": [1440, 900],
  "screens": [{
    "name": "rules list",
    "proto": { "url": "docs/prototypes/rules.html", "actions": [{ "click": "#variant-3" }] },
    "impl":  { "url": "http://localhost:3000/rules", "storageState": "auth.json", "actions": [{ "wait": "[data-testid=rule-row]" }] },
    "elements": [
      { "name": "rule row", "proto": ".rule-row", "impl": "[data-testid=rule-row]", "states": ["default", "hover", "active"] }
    ]
  }]
}

url: http(s)/file URL, or a path relative to spec.json. actions: { "click": sel } | { "wait": sel } | { "fill": [sel, text] }.
states: default | hover | active | focus (default: ["default"]). The first match of each selector is measured.
Prints only differences; exit 0 = none, 1 = differences, 2 = error.`;

const PROPS = [
  "font-family", "font-size", "font-weight", "line-height", "letter-spacing", "text-transform", "color",
  "background-color", "background-image", "opacity",
  "padding-top", "padding-right", "padding-bottom", "padding-left",
  "margin-top", "margin-right", "margin-bottom", "margin-left", "gap",
  "border-top-width", "border-top-style", "border-top-color", "border-bottom-width", "border-bottom-color",
  "border-left-width", "border-left-color", "border-right-width", "border-right-color",
  "border-radius", "box-shadow", "outline-width", "outline-color", "cursor", "text-decoration-line",
  "display", "align-items", "justify-content",
];

const specPath = process.argv[2];
if (!specPath) {
  console.log(USAGE);
  process.exit(2);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const specDir = dirname(resolve(specPath));
const toUrl = (u) => (/^[a-z]+:\/\//i.test(u) ? u : pathToFileURL(isAbsolute(u) ? u : join(specDir, u)).href);

let chromium;
try {
  ({ chromium } = createRequire(join(process.cwd(), "noop.js"))("playwright"));
} catch {
  console.error("style-diff: playwright not found from", process.cwd(), "- run from a project that has it installed");
  process.exit(2);
}

const round = (v) => v.replace(/-?\d+\.\d+/g, (n) => String(Math.round(Number(n) * 2) / 2));

async function openPage(browser, side) {
  const [width, height] = spec.viewport ?? [1440, 900];
  const context = await browser.newContext({
    viewport: { width, height },
    storageState: side.storageState ? resolve(specDir, side.storageState) : undefined,
  });
  const page = await context.newPage();
  await page.goto(toUrl(side.url), { waitUntil: "networkidle" });
  await page.addStyleTag({ content: "*,*::before,*::after{transition:none!important;animation:none!important}" });
  for (const a of side.actions ?? []) {
    if (a.click) await page.click(a.click);
    else if (a.wait) await page.waitForSelector(a.wait);
    else if (a.fill) await page.fill(a.fill[0], a.fill[1]);
  }
  return page;
}

async function measure(page, selector, state) {
  const el = page.locator(selector).first();
  if ((await el.count()) === 0) return null;
  await page.mouse.move(0, 0);
  if (state === "hover" || state === "active") await el.hover();
  if (state === "active") await page.mouse.down();
  if (state === "focus") await el.focus();
  const styles = await el.evaluate((node, props) => {
    const cs = getComputedStyle(node);
    const r = node.getBoundingClientRect();
    return { ...Object.fromEntries(props.map((p) => [p, cs.getPropertyValue(p)])), width: `${r.width}px`, height: `${r.height}px` };
  }, PROPS);
  if (state === "active") await page.mouse.up();
  if (state === "focus") await el.blur();
  return Object.fromEntries(Object.entries(styles).map(([k, v]) => [k, round(v)]));
}

const browser = await chromium.launch();
let diffs = 0;
let errors = 0;
try {
  for (const screen of spec.screens) {
    const proto = await openPage(browser, screen.proto);
    const impl = await openPage(browser, screen.impl);
    for (const el of screen.elements) {
      for (const state of el.states ?? ["default"]) {
        const where = `${screen.name} · ${el.name} · ${state}`;
        const [a, b] = [await measure(proto, el.proto, state), await measure(impl, el.impl, state)];
        if (!a || !b) {
          console.log(`${where} · not found in ${!a ? `proto (${el.proto})` : `impl (${el.impl})`}`);
          errors++;
          continue;
        }
        for (const prop of Object.keys(a)) {
          if (a[prop] !== b[prop]) {
            console.log(`${where} · ${prop} · ${a[prop]} → ${b[prop]}`);
            diffs++;
          }
        }
      }
    }
    await proto.context().close();
    await impl.context().close();
  }
} finally {
  await browser.close();
}
console.log(errors ? `${diffs} differences, ${errors} elements not found` : diffs ? `${diffs} differences` : "no differences");
process.exit(errors ? 2 : diffs ? 1 : 0);
