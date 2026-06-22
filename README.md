# pi-Agent: Sandboxed AI Coding Assistant for any project

**pi-Agent** is a secure, sandboxed AI coding assistant that wraps the `pi` CLI to give an
AI brain autonomous, *verified* code-modification on **any project**. It runs pi confined
by a macOS Seatbelt profile, injects a codebase map so the agent navigates instead of
blind-reading, and gates runs with dedup/rate/token controls. Extracted from an automated
trading platform but project-agnostic — point `PI_DIR` at any git repo.


<img width="1280" height="766" alt="image" src="https://github.com/user-attachments/assets/c295fef4-5140-48b7-9614-6874560a34ba" />

<img width="2560" height="1516" alt="image" src="https://github.com/user-attachments/assets/0ac5f5d0-9711-4201-bcfe-242e25caa419" />

<img width="1916" height="1442" alt="image" src="https://github.com/user-attachments/assets/fe727857-1f48-410d-9730-9e852cbd1c1e" />



## Overview

This agent bridges the gap between AI decision-making and code execution in the app platform. It provides three operational modes:

- **`off`** – No pi execution (default)
- **`readonly`** – Read-only analysis only
- **`full`** – Full read/write/edit/bash capabilities (sandboxed)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 App Platform AI Brain                   │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────┐   │
│  │ AI Brain    │    │ pi_runner.js│    │ pi-sandboxed  │   │
│  │ (app_       │───▶│ (bridge)    │───▶│ .sh          │   │
│  │ monitor.js) │    │             │    │ (sandbox)    │   │
│  └─────────────┘    └─────────────┘    └──────────────┘   │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                Sandboxed Environment                  │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │ pi CLI with read/bash/edit/write tools          │  │ │
│  │  │ • Filesystem confined to project directory       │  │ │
│  │  │ • No network access                              │  │ │
│  │  │ • No parent directory traversal                  │  │ │
│  │  └─────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Key Features

### 1. **Security-First Sandboxing**
- **macOS Seatbelt profiles** (`pi-sandbox.sb`) restrict filesystem access
- **No network access** from within the sandbox
- **No parent directory traversal** (confined to project folder)
- **Tool-based permissions** – `readonly` mode restricts to read-only operations

### 2. **Autonomous Operation**
- **No human intervention required** – pi runs with explicit autonomy rules
- **Error recovery** – Iterates through failures, doesn't stop at first error
- **Context-aware** – Injects project knowledge graph for orientation
- **Model fallback** – Uses OpenRouter DeepSeek V3.1 for reliable tool calling

### 3. **Project Integration**
- **Brain-controlled** – Activated by AI brain cycles
- **Dashboard updates** – Can rebuild and deploy dashboards
- **Data pipeline** – Can fix broken data files, update JSON state
- **Code maintenance** – Can apply fixes, refactor, and optimize

## Generic by design — clone it as a child of your project

This agent is meant to be **git-cloned as a child folder** of the project it edits. The
sandboxed project (`DIR`) then **defaults to the parent** — so pi reads the parent's
`AGENTS.md`, injects the parent's graphify map, and is confined to the parent project
(which includes this nested agent dir). The agent's own assets — the `pi` binary, the
Seatbelt profile, and `.env` (your keys) — always come from the agent folder, not the
project. The SQL-DB layer is **off by default**. Every path is overridable from the env.

```
your-project/                ← DIR (sandboxed; pi reads its AGENTS.md / app_agent.md)
├── src/  package.json  …     ← the code pi works on
└── pi-agent-standalone/      ← AGENT_DIR (pi binary, pi-sandbox.sb, .env, scripts)
```

## Quick start (child-clone layout)

```bash
cd /path/to/your-project                 # the repo you want pi to edit
git clone https://github.com/kinsha-dev/pi-agent-standalone.git
cd pi-agent-standalone

# Bootstrap: installs deps + the pi-subagents extension, writes a starter AGENTS.md to
# the PARENT if missing, builds the graphify map (if the CLI is present), installs hooks.
./scripts/setup.sh ..                     # ".." = the parent project (default target)

# Put your key in the AGENT's .env, then run a task — DIR defaults to the parent project:
echo "OPENROUTER_API_KEY=sk-or-v1-..." >> .env
./pi-sandboxed.sh -p "fix the failing test in src/utils"
```

**Run against a different / non-parent project:** set `PI_DIR` explicitly —
`PI_DIR=/some/other/repo ./pi-sandboxed.sh -p "…"`. To operate on the **agent repo itself**,
use `PI_DIR="$PWD"` from inside it.

## Configuration

All settings are environment variables (use `.env`). Only `OPENROUTER_API_KEY` is required.

| Variable | Default | Purpose |
|---|---|---|
| `OPENROUTER_API_KEY` | — | **Required.** LLM access (https://openrouter.ai/keys) |
| `PI_BRAIN_MODE` | `off` | `off` \| `readonly` \| `full` |
| `PI_MODEL` | `deepseek/deepseek-chat-v3.1` | Must support **tool-calling** |
| `PI_THINKING` | `low` | Reasoning budget: `off`\|`minimal`\|`low`\|`medium`\|`high`\|`xhigh`. Higher = more tokens. |
| `PI_PROVIDER` | `openrouter` | LLM provider |
| `PI_LOAD_GRAPH` | `on` | Inject the codebase map (`off` to disable) |
| `PI_DIR` | parent of the agent dir | **Target project** to sandbox/operate on (child-clone default) |
| `PI_HOME_DIR` / `PI_BIN` / `PI_SANDBOX_PROFILE` | derived | Override runtime paths |

**Run controls** (stop re-running the same issue or burning the budget):

| Variable | Default | Purpose |
|---|---|---|
| `PI_MAX_RUNS_PER_DAY` | `8` | Hard daily run cap |
| `PI_DAILY_TOKEN_BUDGET` | `250000` | Est. tokens/day before runs are skipped |
| `PI_DEDUP_WINDOW_MIN` | `360` | Same task won't re-run within this window |
| `PI_MIN_INTERVAL_MIN` | `20` | Min minutes between any two runs |
| `PI_FORCE` | — | `1` bypasses all run controls |

**Critical-failure alerts** (off unless `NTFY_TOPIC` is set): when a pi run exits non-zero
or times out — i.e. it could **not** recover the app from the error — the runner sends an
[ntfy](https://ntfy.sh) push so a human knows it's still broken. The same-task dedup guard
means a repeating failure won't re-alert within its window.

| Variable | Default | Purpose |
|---|---|---|
| `NTFY_TOPIC` | — | ntfy topic to publish to. **Setting it enables alerts.** |
| `NTFY_URL` | `https://ntfy.sh` | ntfy server — point at a self-hosted instance to keep alerts private |
| `NTFY_TOKEN` | — | Optional `Bearer` token for protected/self-hosted topics |

Callers of `runPiTask(task, opts)` can force a push on a clean-but-unresolved run with
`opts.notify = true`, or mute one with `opts.notify = false`.

**Optional SQL-DB layer** (off unless set): `PI_SQL_DATA_DIR`, `PI_SQL_APP_STORE_DB`,
`PI_SQL_MEMORY_DB`, `PI_SQL_META_DB`, `PI_SQL_MODE` (`readwrite`|`readonly`),
`PI_SQL_MAX_ROWS`. Only databases that **exist on disk** are granted into the sandbox.

## Usage

### From the AI Brain

```javascript
const { runPiTask } = require('./pi_runner');

// Run a task with pi
await runPiTask("Fix the bug in allocation_agent.js where entry prices are miscalculated", {
  timeout: 120000,  // 2 minutes
  verbose: true
});
```

### Direct Execution

```bash
# Run pi in sandboxed mode
./pi-sandboxed.sh "Analyze the codebase for performance bottlenecks"

# Or via the runner
node pi_runner.js "Check all JSON data files for consistency"
```

### Modes of Operation

Configure via `PI_BRAIN_MODE` in `.env`:

```javascript
// off - No pi execution (safe default)
// readonly - Read-only analysis only
// full - Full sandboxed execution (read/bash/edit/write)
```

## Sandbox Profile (`pi-sandbox.sb`)

`deny default`, then narrow allows. The profile enforces:
- **Writes** only within the project dir, `~/.pi` runtime, temp, and the two trading
  DB files (see below) — nothing else.
- **Reads** of the OS runtime needed to run node + the project dir; other user folders
  (`~/Documents`, `~/.ssh`, sibling projects) stay denied.
- **Network: outbound only** (the LLM API). Inbound/bind are denied so the agent can't
  open a listener (reverse shell / C2 / on-host exfil server).
- **No `~/.pm2` access** — the PM2 daemon runs outside the sandbox; reaching its socket /
  `dump.pm2` would let the confined agent spawn unsandboxed processes (escape).

## SQL Database Access (MCP server + CLI) — optional

> **Opt-in.** This layer is OFF unless you set `PI_SQL_DATA_DIR` (or a `PI_SQL_*_DB`
> path). On a generic project with no SQLite, the agent runs without it and only DBs
> that actually exist on disk are ever granted into the sandbox. The example below
> describes the trading-system setup this agent was extracted from.

The trading state lives in SQLite DBs in the data dir (the project's parent):
`app_store.db` (trade ideas, portfolio, screener, allocations, alerts, analytics — ~30
tables), `memory.db` (sessions, ticker snapshots, signal events, entity facts), and
`meta.db` (`run_history` — per-agent operational telemetry: each LLM call and data_sync
with records/tokens/status, for last-week activity rollups). One shared core
(`db_core.js`, builtin `node:sqlite`, no native build) backs two front-ends:

- **MCP server** (`mcp_sql_server.js`) — stdio MCP for Claude Code / Claude Desktop, for
  **conversational READ-ONLY** queries of the live trading DB. Wired via [`.mcp.json`](.mcp.json)
  with **`PI_SQL_MODE=readonly`** (by policy — see below). Tools: `list_databases`,
  `list_tables`, `describe_table`, `query`. (`execute` is blocked while readonly.)
- **CLI** (`db_cli.js`) — the **write path** and the SQL front-end for everything else
  (the sandboxed `pi` agent, which has no MCP by design; scripts; ad-hoc use). Runs as its
  own process, so its `PI_SQL_MODE` defaults to `readwrite` independent of the MCP server.
  - Read:  `node db_cli.js query app_store "SELECT * FROM trade_ideas WHERE ticker = ?" '["NVDA"]'`
  - Write: `node db_cli.js execute app_store "INSERT INTO <your_table> ..." '[...]'`

> **Why MCP is read-only:** the 9 registered tables are owned by the trading agents
> (`data_store.writeStore` → JSON+DB) and re-synced JSON→DB every ~7s. An MCP write to one
> of those would be reverted by the next sync and could clobber the live JSON the dashboard
> reads. So MCP **reads** the live DB; **writes** go through `db_cli execute` into your OWN
> tables (not in the registry), where they persist cleanly with no sync conflict.

Config (env): `PI_SQL_MODE` (`readwrite` default | `readonly`), `PI_SQL_MAX_ROWS`
(default 1000), `PI_SQL_DATA_DIR` / `PI_SQL_APP_STORE_DB` / `PI_SQL_MEMORY_DB` (paths).
For the sandboxed pi agent, the launchers grant the seatbelt profile access to exactly
those two DB files (plus SQLite's WAL sidecars) — never the parent dir.

Safety rails baked into both front-ends: `query` rejects any non-read statement;
`execute` is gated by `PI_SQL_MODE`; table names in `describe_table` are validated
against an identifier allowlist before any PRAGMA; results are row-capped.

## Knowledge Graph Integration

When `PI_LOAD_GRAPH=on`, the agent injects a codebase map into every task so pi jumps
straight to the right file instead of blind-reading. It prefers, in order:

1. **`app_agent.md`** (≈2k tokens) — a curated, navigable map: module→file index, the
   most-connected hub functions, and (if you add them) curated pipeline/entry-point notes.
2. **`graphify-out/GRAPH_REPORT.md`** sections (≈600 tokens) — summary, god nodes,
   surprising connections, hyperedges — used as a fallback when `app_agent.md` is absent.
3. **nothing** — if neither exists, pi runs without the map (no crash).

Either way it's ~2k tokens vs. ~150k+ for blind-reading core files to learn structure.

### Commit-hook pipeline (keeps the map fresh)

`./scripts/install-hooks.sh /path/to/project` wires the target's `post-commit` hook to:

1. **`graphify hook install`** — rebuilds `graph.json` + `GRAPH_REPORT.md` after each
   commit (code files only, AST, backgrounded, no LLM). Skipped if the `graphify` CLI
   isn't installed.
2. **`scripts/gen_app_agent.py`** — regenerates `app_agent.md` from the freshly rebuilt
   graph (~20s after, detached — never blocks the commit).

Both steps are idempotent and run detached, so commits stay instant. `scripts/setup.sh`
calls this for you. To build the map for the first time: `graphify .` in the target repo.

## Autonomous Operation Rules

The agent includes a preamble that enforces autonomous behavior:

```
=== OPERATING RULES (non-interactive run — read first) ===
You are running headless with NO human available to answer questions mid-task.
- NEVER ask for confirmation, permission, or clarification. There is no one to reply.
- When something is ambiguous, pick the most reasonable interpretation from the codebase
  conventions and state the assumption in your final summary — then proceed.
- Do not stop at the first error. Iterate: read the failing file, apply a fix, re-run
  the relevant check, and repeat until it runs correctly or you have exhausted reasonable attempts.
- Prefer the smallest change that makes it work. Verify before declaring done — quote the
  command you ran and its output in your summary.
- If a task is genuinely impossible (missing file, missing credential), say so concisely
  and stop — do not loop forever and do not ask a question instead.
=== END OPERATING RULES ===
```

## Real-World Use Cases

### 1. **Dashboard Maintenance**
```javascript
// Rebuild dashboard when data changes
await runPiTask("The dashboard.html shows stale data. Regenerate it with the latest market data");
```

### 2. **Bug Fixes**
```javascript
// Fix allocation agent price calculation bug
await runPiTask("allocation_agent.js is calculating entry prices incorrectly. They should be real per-share prices, not dollar notionals. Find and fix the bug.");
```

### 3. **Data Recovery**
```javascript
// Recover from corrupted JSON
await runPiTask("portfolio_state.json is malformed JSON. Read it, identify the corruption, fix it, and write it back valid.");
```

### 4. **Performance Optimization**
```javascript
// Optimize slow dashboard generation
await runPiTask("dashboard_writer.js takes 5+ seconds to generate HTML. Profile it and apply optimizations to reduce generation time.");
```

## Safety Considerations

1. **Filesystem confinement** – Cannot access files outside the project (plus the two
   explicitly-granted DB files); confirmed via EPERM on sibling files.
2. **Outbound-only network** – Can reach the LLM API but cannot open a listener.
3. **Tool restrictions** – `readonly` mode for analysis only; SQL `query` rejects writes.
4. **Git safety** – `safe-push.sh` blocks secrets/backups, scans the diff for keys,
   never force-pushes, and feeds the token via env (no script-body injection).
5. **Secrets protection** – `.env` files are gitignored and blocked from commits.
6. **No PM2 reach** – the out-of-sandbox PM2 daemon is unreachable from the jail.

## Files

- `pi_runner.js` – Main bridge module (modes, run controls, map injection, parametrized paths)
- `pi-sandboxed.sh` – Sandbox execution wrapper
- `pi-sandbox.sb` – macOS Seatbelt sandbox profile
- `safe-push.sh` – Guarded commit + push (the only git-write path)
- `scripts/setup.sh` – One-shot bootstrap against any target project
- `scripts/install-hooks.sh` – Install the graphify + app_agent.md commit-hook pipeline
- `scripts/gen_app_agent.py` – Generic `app_agent.md` generator from a graphify graph
- `pi_task.js` – Generic one-shot task runner: `node pi_task.js "task"` (bypasses run controls via `force`)
- `.claude/commands/piworkflow.md` – `/piworkflow` command: orchestrate task(s) via pi + the `pi-subagents` extension (worker implements, reviewer reviews, parallel + review loop)
- `db_core.js` – Shared SQLite access layer (`node:sqlite`) — optional
- `mcp_sql_server.js` – MCP (stdio) server over the DBs — optional
- `db_cli.js` – CLI front-end for the sandboxed pi agent — optional
- `.mcp.json` – Claude Code MCP wiring
- `AGENTS.md` – Operating context and guidelines
- `package.json` – Dependencies

## License

MIT
