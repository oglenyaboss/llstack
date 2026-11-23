---
name: github-projects-api
description: "Use when reading or editing a GitHub Projects v2 board through gh GraphQL: fields, items, views, and their known limits."
---

# GitHub Projects v2 through `gh`

The board is an optional planning view. Issues hold the record; readiness lives in issue labels. A card in a Done column is not owner acceptance, and a board status is not a triage role.

## Rules

- Never mirror every issue. Add what is being planned or worked, and leave the rest in the tracker.
- Resolve project, field, and option ids at run time with `gh project field-list` and GraphQL reads. Do not commit `PVT_`, `PVTI_`, or `PVTSSF_` ids or numeric option ids to a repo file.
- A mutation needs an explicit request naming the project and the item. Do not run one while exploring.
- Read the item back after a write. A successful mutation response is not proof that the field shows the intended value.
- Do not promise unattended setup of anything the API cannot create. See [references/api-capability-notes.md](references/api-capability-notes.md).

## Find the project

`gh project` takes a project number and an owner, not a node id:

```bash
PROJECT=<number>   # from the Workflow section's "GitHub Project: <owner>/<number>", or ask
OWNER=<owner>

gh project field-list "$PROJECT" --owner "$OWNER"
gh project view "$PROJECT" --owner "$OWNER"
```

`field-list` gives the field ids and, for each single-select field, its option ids. Those are what the mutations below need, and they change per project, so read them every run.

## Variables

The recipes below use four ids that all come from read-only calls:

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PROJECT_NODE_ID=$(gh project view "$PROJECT" --owner "$OWNER" --format json --jq .id)
# from `gh project field-list "$PROJECT" --owner "$OWNER" --format json`
FIELD_ID=<field id>
OPTION_ID=<single-select option id>
```

`$PROJECT` stays the project number for `gh project` commands. `$PROJECT_NODE_ID` is the `PVT_` id that GraphQL needs. Do not reuse one for the other.

## Fields

The API cannot rename the options of the built-in `Status` field. Two workable postures:

- Use the built-in `Status` as it ships and accept its option names.
- Create a custom single-select field, for example `Status`, with the options the team wants, and hide the built-in field from every view through `visibleFieldIds`.

```bash
gh project field-create "$PROJECT" --owner "$OWNER" \
  --name "Status" --data-type SINGLE_SELECT \
  --single-select-options "Inbox,Ready,In Progress,Review,Done"
```

Iteration fields are the exception. `gh project field-create` still offers only TEXT, SINGLE_SELECT, DATE, and NUMBER, so an iteration field needs a GraphQL mutation:

```graphql
mutation {
  createProjectV2Field(input: {
    projectId: "PVT_..."
    dataType: ITERATION
    name: "Cycle"
    iterationConfiguration: {
      startDate: "2026-01-05"
      duration: 14
      iterations: [{ startDate: "2026-01-05", duration: 14, title: "C1" }]
    }
  }) { projectV2Field { ... on ProjectV2IterationField { id } } }
}
```

Updating an iteration field replaces the entire list. Send every iteration, including completed ones with their ids. An iteration you leave out is deleted, and the items lose their value. Read the current configuration first, change only the dates or add one iteration, then send the whole list back.

A team that does not need iterations can use a single-select of cycle names instead. It is one less mutation shape to get wrong.

## Items

Add an issue or PR to the board:

```bash
CONTENT_ID=$(gh api "repos/$OWNER_REPO/issues/$N" --jq .node_id)
ITEM_ID=$(gh api graphql -f query='
mutation($project: ID!, $content: ID!) {
  addProjectV2ItemById(input: {projectId: $project, contentId: $content}) {
    item { id }
  }
}' -f project="$PROJECT_NODE_ID" -f content="$CONTENT_ID" --jq .data.addProjectV2ItemById.item.id)
```

Set a single-select value:

```bash
gh api graphql -f query='
mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $project, itemId: $item, fieldId: $field
    value: {singleSelectOptionId: $option}
  }) { projectV2Item { id } }
}' -f project="$PROJECT_NODE_ID" -f item="$ITEM_ID" -f field="$FIELD_ID" -f option="$OPTION_ID"
```

Read item values. `fieldValues` is a union, so select through `__typename` and an inline fragment:

```bash
gh api graphql -f query='
query($project: ID!) {
  node(id: $project) {
    ... on ProjectV2 {
      items(first: 100) {
        nodes {
          id
          content { ... on Issue { number title } }
          fieldValues(first: 20) {
            nodes {
              __typename
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2FieldCommon { name } }
              }
            }
          }
        }
      }
    }
  }
}' -f project="$PROJECT_NODE_ID"
```

Remove an item from the board, which leaves the issue open:

```graphql
mutation { deleteProjectV2Item(input: {projectId: "PVT_...", itemId: "PVTI_..."}) { deletedItemId } }
```

Archive instead of deleting when the card may come back:

```bash
gh project item-archive "$PROJECT" --owner "$OWNER" --id "$ITEM_ID"
```

## Views

Views are partly scriptable. `createProjectV2View` accepts name, layout, and configuration. `updateProjectV2View` also accepts a filter. Column and row grouping are not accepted by the API; a human sets them in the UI.

`configuration.visibleFieldIds` is the one way to hide the built-in `Status` from a view. List every field the view should show, explicitly. A field left out is hidden, which is easy to mistake for a permission problem.

```graphql
mutation {
  updateProjectV2View(input: {
    viewId: "PVTV_..."
    filter: "label:\"ready-for-agent\""
    configuration: { visibleFieldIds: ["PVTF_...", "PVTF_..."] }
  }) { projectV2View { id name filter } }
}
```

## Automation

The API creates no workflows. It can only delete one. Auto-add by label, and status changes on close, are UI settings. Setup does not attempt them, and neither should this skill unless the user asks for a checklist.

A useful manual checklist for the owner:

1. Workflow "Item added", filter to the label that means planned work.
2. Workflow "Item closed", set the status field to the closed value.
3. Views: one filtered by the triage role, one by the working status, one grouped by area.
4. Hide the built-in `Status` from every view that uses a custom status field.

Number the steps and stop. Do not claim a workflow was created.

## Pitfalls

- Substituting an id inside a single-quoted `-f query='...'` with a newline or space around it produces "option Id does not belong to the field". Put ids in GraphQL variables, as above.
- Reading `.field.name` directly from the union fails with a selection mismatch. Always use `... on ProjectV2FieldCommon`.
- `deleteProjectV2Item` is the mutation. `removeProjectV2Item` does not exist in the schema.
- The `deleteIssue` payload has no `success` field; select `deletedIssueId`.
- `deleteProjectV2` returns the project under `.projectV2.id`; there is no `deletedProjectId`.
- `gh issue create` has no `--format`; the issue number comes from the URL it prints.
- Before deleting a label, check its use: `gh issue list --label <name> --state all --limit 5`.

## Capability notes

The dated list of what is verified, what is carried from an operator's notes, and what is UI-only: [references/api-capability-notes.md](references/api-capability-notes.md). Read it before designing a script, and do not extend a claim past its date.

The skill's origin and the list of changes: [references/provenance.md](references/provenance.md).
