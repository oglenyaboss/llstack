# An independent skeptic (experimental reference)

Experimental add-on to `herdr-delegate`. Off by default: it adds a review pass, it never replaces the risk policy's reviewers and never lowers a tier. `hd` below is the delegate driver.

You verify the diff against your own brief, so a wrong Decision or a missing Trap passes your verification. The skeptic attacks the diff against the spec instead: a scout on a model family different from yours that gets the spec and the diff and never your brief.

Run it after the Loop's Verify step accepts a writer's diff, when any of these holds:

- a wrong change is irreversible or costly: migrations and data deletion, money, auth and permissions, concurrency and transactions, or the project's risk tier is High;
- the brief carries Decisions the user did not confirm in this session, or the spec is ambiguous;
- the task failed two corrections: run it on the last diff before you re-brief.

Fill [skeptic-brief.md](skeptic-brief.md) with the whole task's diff: `hd diff w1` when the task took one ask; after corrections, `git diff <commit the task started from>` with new files added via `git add -N`. Then launch through your client's shell tool, picking an agent and model from another family than yours:

```
hd diff w1 > /tmp/w1.patch
hd spawn sk-x scout --agent codex      # or --model <other family>; codex takes --thinking low|medium|high|xhigh, default high
hd ask sk-x @skeptic.md
```

Codex starts only in a folder it trusts; on a trust dialog at spawn, ask the user to run `codex` there once. Strong reasoning models are slow: keep working while it runs. Verify each finding like a reviewer's (open its file:line), fix confirmed ones through the Loop, and `hd note sk-x` every false alarm.

## Status

Experimental. Keep it if, over a couple of weeks, it finds at least one confirmed high or medium defect the lead missed; narrow its triggers or drop it if its findings are false alarms (see the `hd note` entries) or duplicate the regular review.

## Limits

Nothing enforces the model family: picking the same family as the lead turns the skeptic into a second opinion with the same blind spots. It also needs a second executor model reachable through Herdr, which is why it stays opt-in.
