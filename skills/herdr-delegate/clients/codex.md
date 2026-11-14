# Codex launch and wait

`hd` controls pi agents in Herdr. Codex shell process handles and `functions.exec` cell handles track the commands waiting for those agents. Native Codex subagent wait tools track a different set of agents.

When no independent work remains, keep the waiting loop inside one `functions.exec` cell. Set its outer `yield_time_ms` to the task's wait budget, up to the default 50-minute `hd` timeout. Shell polling inside JavaScript does not require another model inference. Print the final result only.

```js
// @exec: {"yield_time_ms": 3000000, "max_output_tokens": 2000}
let result = await tools.exec_command({
  cmd: "/path/to/herdr-delegate/hd ask NAME @/path/to/brief.md",  // this skill's directory
  yield_time_ms: 1000,
  max_output_tokens: 2000
});
let output = result.output;
while (result.session_id !== undefined) {
  result = await tools.write_stdin({
    session_id: result.session_id,
    chars: "",
    yield_time_ms: 50000,
    max_output_tokens: 2000
  });
  output += result.output;
}
text({exit_code: result.exit_code, output});
```

For independent asks, run this launch-and-wait function for each command inside one cell with `Promise.allSettled`, then inspect every result. When doing independent work first, retain the launched processes' `session_id` values and use the same in-cell wait loop once ready to wait.

Respect higher-priority session requirements for progress updates or maximum blocking waits: shorten the outer yield only when those require returning control. Such sessions cannot promise zero intermediate model calls.

If the cell does yield `Script running with cell ID ...`, resume it through `functions.wait` using the remaining wait budget allowed by session instructions. A `cell_id` belongs to `functions.wait`; a `session_id` belongs to `write_stdin`. Once the command finishes, handle the envelope using the main Loop. For `STATUS: still_working`, continue with `hd wait <name>` using the same recipe. If an interrupted turn lost the process handle, recover through `hd wait <name>` rather than submitting the brief again.

`yield_time_ms` controls when Codex gets control back. It is not the agent's deadline. Use the running command's wait handle for routine waiting; terminal peeks are for investigating a specific problem.
