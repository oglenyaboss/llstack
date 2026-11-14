# Provenance

This skill was adapted from an operator's private GitHub Projects skill. The private file is not part of this repository.

## Kept

- The quirk list: project number plus `--owner`, unrenameable built-in `Status` options, grouping as UI-only, `visibleFieldIds` as the way to hide a field, no workflow creation through the API, and the item and field mutation shapes.
- The pitfalls: whitespace around a substituted id, union reads that need an inline fragment, `deleteProjectV2Item` naming, the `deleteIssue` payload, and checking label use before deletion.
- The practice of dating API claims against a `gh` version.

## Changed

- English throughout, and all personal paths, org names, account names, project numbers, and stored ids removed. The project number comes from the project's Workflow section; ids are read at run time with `gh project field-list`.
- The skill is framed as an optional planning layer: issues hold the record, the board is a view. Board status is explicitly separate from triage labels and from owner acceptance.
- Recipes use GraphQL variables instead of shell interpolation inside `-f query='...'`, which removes the whitespace class of failure rather than warning about it.
- The iteration note was corrected from "the API cannot create iterations" to "the CLI cannot, the GraphQL mutation can", matching a later operator check. Both versions carried dates in the older notes; the later one wins.
- A capability-notes reference separates what was verified locally in this build from what was carried forward. Nothing carried is described as verified.
- Setup writes no ids into generated docs and creates no board files when the board is disabled.
- The workflow checklist is presented as manual steps for a human, with no claim that setup performs them.

## Not copied

No board data, item ids, field ids, account names, or session material from the earlier usage.
