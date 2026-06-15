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

## Generic by design

Nothing here is hard-wired to a particular project. Point `PI_DIR` at **any git repo**
and the agent sandboxes itself to that repo, reads *its* `AGENTS.md`, and (optionally)
injects *its* graphify map. The SQL-DB layer is **off by default** and only activates if
you point it at real databases. Every path is overridable from the environment.

## Quick start — run against any project

```bash
git clone https://github.com/kinsha-dev/pi-agent-standalone.git
cd pi-agent-standalone

# One-shot bootstrap for a target project: deps, starter AGENTS.md,
# graphify map (if the CLI is present), and the commit-hook pipeline.
./scripts/setup.sh /path/to/your/project

# Put your key in .env, then run a task against that project:
echo "OPENROUTER_API_KEY=sk-or-v1-..." >> .env
PI_DIR=/path/to/your/project ./pi-sandboxed.sh -p "fix the failing test in utils"
```

## Configuration

All settings are environment variables (use `.env`). Only `OPENROUTER_API_KEY` is required.

| Variable | Default | Purpose |
|---|---|---|
| `OPENROUTER_API_KEY` | — | **Required.** LLM access (https://openrouter.ai/keys) |
| `PI_BRAIN_MODE` | `off` | `off` \| `readonly` \| `full` |
| `PI_MODEL` | `deepseek/deepseek-chat-v3.1` | Must support **tool-calling** |
| `PI_PROVIDER` | `openrouter` | LLM provider |
| `PI_LOAD_GRAPH` | `on` | Inject the codebase map (`off` to disable) |
| `PI_DIR` | this repo | **Target project** to sandbox/operate on |
| `PI_HOME_DIR` / `PI_BIN` / `PI_SANDBOX_PROFILE` | derived | Override runtime paths |

**Run controls** (stop re-running the same issue or burning the budget):

| Variable | Default | Purpose |
|---|---|---|
| `PI_MAX_RUNS_PER_DAY` | `8` | Hard daily run cap |
| `PI_DAILY_TOKEN_BUDGET` | `250000` | Est. tokens/day before runs are skipped |
| `PI_DEDUP_WINDOW_MIN` | `360` | Same task won't re-run within this window |
| `PI_MIN_INTERVAL_MIN` | `20` | Min minutes between any two runs |
| `PI_FORCE` | — | `1` bypasses all run controls |

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

- **MCP server** (`mcp_sql_server.js`) — stdio MCP for Claude Code and any MCP client.
  Wired via [`.mcp.json`](.mcp.json). Tools: `list_databases`, `list_tables`,
  `describe_table`, `query` (read-only), `execute` (write/DDL).
- **CLI** (`db_cli.js`) — for the sandboxed `pi` agent, which has no MCP by design.
  `node db_cli.js query app_store "SELECT * FROM trade_ideas WHERE ticker = ?" '["NVDA"]'`

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
- `db_core.js` – Shared SQLite access layer (`node:sqlite`) — optional
- `mcp_sql_server.js` – MCP (stdio) server over the DBs — optional
- `db_cli.js` – CLI front-end for the sandboxed pi agent — optional
- `.mcp.json` – Claude Code MCP wiring
- `AGENTS.md` – Operating context and guidelines
- `package.json` – Dependencies

## License

MIT
