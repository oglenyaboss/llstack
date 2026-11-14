# API capability notes

What is known about the Projects v2 API, when it was checked, and how much weight each line carries.

Two kinds of entry:

- **Verified locally** means the check ran in this repository's build on the date shown, against the `gh` version shown, without a network call. These are checks made through the CLI's own help output.
- **Carried** means the claim comes from an operator's notes on an earlier date. This build makes no live GitHub calls, so it did not re-test them. Treat a carried line as likely true and verify it before building on it.

## CLI commands

| Claim | Date | `gh` | Basis |
|---|---|---|---|
| `gh project` subcommands take a project number with `--owner`, not a node id. | 2026-11-13 | 2.103.3 | Verified locally: `gh project field-list <n> --owner <login>` in help text and examples. |
| `gh project field-create` accepts only TEXT, SINGLE_SELECT, DATE, NUMBER. No ITERATION. | 2026-11-13 | 2.103.3 | Verified locally in `--help`. |
| `gh project item-archive`, `item-add`, `item-edit`, `item-list`, `item-delete` exist. | 2026-11-13 | 2.103.3 | Verified locally in `gh project --help`. |
| `gh issue create` accepts `--type` and `--parent`. | 2026-11-13 | 2.103.3 | Verified locally in `--help`, with examples. |
| `gh issue create` has no `--format`; the number comes from the printed URL. | 2026-11-13 | 2.103.3 | Verified locally: no such flag in `--help`. |

## GraphQL behavior

| Claim | Date | `gh` | Basis |
|---|---|---|---|
| Iteration fields can be created and updated through `createProjectV2Field` / `updateProjectV2Field` with `iterationConfiguration`, though not through the CLI. | 2026-10-20 | 2.102 | Carried. Not re-tested here. |
| An iteration update replaces the whole list. Omitting completed iterations deletes them and clears item values; sending their ids preserves the values. | 2026-10-20 | 2.102 | Carried. Highest-consequence claim in this file: read the configuration before writing. |
| Built-in `Status` options cannot be renamed. No `updateProjectV2FieldOption` mutation exists. | 2026-09-14 | 2.98 | Carried. |
| `createProjectV2View` accepts name, layout, configuration. `updateProjectV2View` adds filter. | 2026-09-14 | 2.98 | Carried. |
| `groupByFields` and `verticalGroupByFields` are rejected. Grouping is UI-only. | 2026-09-14 | 2.98 | Carried. |
| `configuration.visibleFieldIds` is the way to hide a field from a view, and the list must name every visible field. | 2026-09-14 | 2.98 | Carried. |
| No workflow creation through the API. `deleteProjectV2Workflow` exists. | 2026-09-14 | 2.98 | Carried. |
| `addProjectV2ItemById` and `updateProjectV2ItemFieldValue` behave as shown in the skill recipes. | 2026-09-14 | 2.98 | Carried. Recipes rewritten to use GraphQL variables instead of string substitution. |
| Issue dependencies can be added with `POST repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by` and `issue_id` set to the blocker's database id. | 2026-11-13 | 2.103.3 | Carried from the author's tracker docs by way of the issue workflow; not re-tested. |
| `issue_dependencies_summary.blocked_by` counts open blockers only. | 2026-11-13 | 2.103.3 | Carried, same source. |
| `gh issue create --parent` creates a sub-issue. | 2026-11-13 | 2.103.3 | Flag verified locally; server behavior carried. |

## UI-only, and therefore not promised

- Auto-add an item when a label is applied.
- Change a field value when an issue closes.
- View grouping by column or row.
- Any workflow rule.

Setup and this skill may hand the owner a numbered checklist for these. They never claim the API did it.

## What this build did not do

No GraphQL request, no `gh api` call, no mutation, and no model invocation. The carried rows above are the reason this file exists: they preserve the date and the version so a reader can decide how much to trust them before spending a live call.
