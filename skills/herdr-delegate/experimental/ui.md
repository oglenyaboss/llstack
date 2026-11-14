# UI from an approved prototype (experimental reference)

Experimental add-on to `herdr-delegate`. Off by default: it does not change the Loop, and it never weakens a review gate. `hd` below is the delegate driver.

The approved prototype is the spec for **how it looks**: layout, styles, states, copy. It is **not** a spec for logic or data: its script, constants, dictionaries, and sample data are demo stand-ins built on one project's snapshot.

- **Before approval:** a scout maps the prototype's tooltips, buttons, badges, drawers, and modals to the service's existing components (file:line); every mismatch goes to the user.
- **Brief:** a table maps each element to its source: `prototype.html:120-140 .rule-row` → target component, ported 1:1 onto the service's tokens, appearance only. A deviation from the prototype enters the brief only as a list item the user approved in this session.
- **Brief, logic and data:** every constant, map, or helper in the prototype's script (labels, icons, phrase builders, filters) maps to its real source: a DB field via the API, an existing registry (file:line), or a decision you name. Never ported from the prototype.
- **Done when:** `node style-diff.mjs <spec.json>`, run from the project directory (it loads Playwright from the project's `node_modules`), shows no differences beyond the approved deviations, for every mapped element in its default, hover, and active states. Run it bare for the spec format. Screenshots are for the user; acceptance is the style diff.
- **Verify:** the writer's diff also passes its style diff before you accept it.
- **Before showing the user:** the sidekick opens the page on the stand with real data, 3 to 5 real records including the longest names and the rare states, and lists what breaks.
- **TUI:** no CSS to diff, so acceptance is screen text: each Acceptance case is keys → expected `tmux capture-pane -p` output. Before showing the user, the sidekick drives every key path (switching, input, paste, exit, mouse) in tmux on real data and lists what breaks. PNG frames only for colors.

## Status

Experimental. Used on two projects (one web, one TUI); the style diff ran rarely, so whether it cuts the fixes users find after "done" is unmeasured. Keep it if it earns that; drop it otherwise. `style-diff.mjs` needs Node and Playwright installed in the project, and it starts a browser, so it does not run in the offline test suite.

## Limits

The style diff compares first-match computed styles of the elements you name. It does not know which elements the prototype has and the implementation lacks, so the element table in the brief carries that check.
