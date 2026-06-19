---
description: Run task(s) through pi + pi-subagents (worker implements, reviewer reviews; parallel + review loop)
argument-hint: <task>  — separate multiple tasks with `;;` or new lines
---

Run the supplied task(s) through **pi with the `pi-subagents` extension**. pi is the orchestrator: it delegates each task to a `worker` subagent (implement) and a `reviewer` subagent (review loop), running independent tasks in parallel. pi is the only code executor; you (Claude) launch it once and review the final result.

Raw input: $ARGUMENTS

Do this:

1. **Parse** the raw input into tasks: split on `;;` or on newlines; trim; drop empties. If there is no delimiter, treat it as ONE task. Use judgment — an illustrative example inside a task is NOT a separate task. Enrich a task with conversation context where it helps pi act.
2. If empty, ask for at least one task and stop.
3. **Echo** the parsed tasks, numbered.
4. **Run ONE pi invocation SYNCHRONOUSLY in the foreground** (Bash tool, timeout ~600000 ms, do NOT background) with a tool-calling-capable model so the subagents work:
   ```bash
   PI_MODEL=openai/gpt-4o-mini node pi_task.js "<orchestration prompt below, with the parsed tasks filled in>"
   ```
5. **Review**: relay pi's per-task summary, then independently inspect `git diff` and run cheap verifications (`node --check`, grep). Flag anything off-spec and re-run that task if needed.

### Orchestration prompt to pass to pi (fill in the numbered TASKS):

```
You have the `subagent` tool (pi-subagents). Complete these tasks:
<numbered task list>

Orchestration rules:
- Delegate each IMPLEMENTATION task to a `worker` subagent. Run tasks that touch DIFFERENT files as PARALLEL worker subagents; run tasks touching the SAME file sequentially to avoid conflicts.
- For INVESTIGATION-only tasks, use a `scout` subagent (read-only). For risky design calls, consult `oracle` first.
- After each worker finishes, run a `reviewer` subagent on that change (verify it matches the task, correctness, edge cases, simplicity). Apply review fixes worth doing — up to 2 review rounds per task.
- Make the smallest change that satisfies each task. Verify changed .js files with `node --check`.
Return a concise PER-TASK report: the files/lines the worker changed, the reviewer's verdict, and anything left open.
```

### Rules / notes
- **Model matters:** launch with a tool-calling model — `openai/gpt-4o-mini` (fast) or `deepseek/deepseek-chat`. pi's configured default `deepseek-v4-flash` is BROKEN for tool-calling and **subagents inherit the parent model**, so they will hang on it. See [[feedback-pi-task-runner]].
- **Sync only** — foreground, no `pi_async`/watchdog/background (that approach caused cross-kill chaos).
- Builtin pi-subagents agents: `scout`, `researcher`, `planner`, `worker`, `reviewer`, `oracle`, `context-builder`, `delegate`.
- The lean `pi_chain.js` and the Claude-side `pi-hybrid-chain` workflow still exist, but this command now prefers pi's own subagent orchestration.
