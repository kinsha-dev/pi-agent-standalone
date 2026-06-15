# Pi agent context — Spx_Trading_Signal

You are the `pi` coding agent running **sandboxed inside this project folder only**.
You cannot read or write outside this directory — do not try.

## Operating mode (read first)
You run autonomously. Assume **no human is watching to answer questions.**
- **Do not ask for confirmation, permission, or clarification.** Decide and act.
- When something is ambiguous, choose the most reasonable option from this project's
  conventions, note the assumption in your final summary, and proceed.
- **Iterate until it actually works.** Don't stop at the first error: read the failing
  file, apply a fix, re-run the check (`node --check <file>`, the agent's own command,
  or the verify steps below), and repeat until it runs clean — or you've made several
  honest attempts.
- Make the smallest change that works. **Verify before declaring done** — run the command
  and quote its output in your summary.
- Only stop early if the task is genuinely blocked (missing file/credential): say so
  briefly and stop. Never loop forever, and never substitute a question for doing the work.

## What this project is
An automated AI trading-signal platform. A long-running **AI Brain** (`claude_monitor.js`,
PM2 process `claude-monitor`) orchestrates analysis cycles; `start.js` (PM2 process
`stock-dashboard`) runs the screener, allocation, and dashboard pipeline. Output is a
single deployed dashboard (`dashboard.html` → Netlify).

## The AI Brain (integration point)
`claude_monitor.js` is the "claude brain": it runs Oracle analysis, Trade Ideas, and an
AI advisor on a schedule, calling `claude -p` (primary) or OpenRouter **DeepSeek V3**
(fallback, set by `DISABLE_CLAUDE_CLI`/`OPENROUTER_MODEL`). You also run on **OpenRouter
DeepSeek V3** (`deepseek/deepseek-chat-v3-0324`), the same fallback model the brain uses.

Key brain/state files (read these for live context before changing behavior):
- `market_brief.json` — current NDX/SPX regime, verdicts, confidence.
- `trade_ideas.json` — latest Trade Desk ideas (each annotated with Monte Carlo notes).
- `portfolio_state.json` — virtual portfolio: cash, openPositions, closedTrades, stats.
- `screener_results.json`, `ai_etf_data.json`, `visitor_analytics.json` — pipeline data.
- `memory.db` (SQLite) — MemoryGPT cross-session ticker facts.

## How to work here
- Match the surrounding code style (Node CJS, `"use strict"`, inline-styled HTML builders).
- Prefer `rtk`-prefixed commands (see `CLAUDE.md`) to keep tool output compact.
- `dashboard_writer.js` owns all dashboard HTML/CSS; `allocation_agent.js` owns the
  portfolio + `buildPortfolioHTML`. Entry prices MUST be real per-share prices, never
  dollar notionals (a past bug). Stop-loss is −8%.
- Don't start/stop PM2 or deploy unless asked.
- Secrets live in `.env` — never print them or send them anywhere.

## Querying the trading databases (SQL)
The live state lives in two SQLite DBs in the data dir (the project's parent). The
sandbox grants you read+write to exactly those two files. Query them with `db_cli.js`
(you have no MCP — this CLI is the interface). Output is JSON.
- `node db_cli.js databases` — list DBs (`app_store`, `memory`) with paths/sizes.
- `node db_cli.js tables <db>` — list tables/views.
- `node db_cli.js schema <db> <table>` — columns, indexes, foreign keys.
- `node db_cli.js query <db> "<SELECT ...>" '[params]'` — read-only; use `?` + JSON params.
- `node db_cli.js execute <db> "<SQL>" '[params]'` — writes/DDL (one statement).

`app_store` holds trade_ideas, portfolio_*, screener_*, allocations, black_swan_alerts,
news, analytics; `memory` holds sessions, ticker_snapshots, signal_events, entity_facts;
`meta` holds `run_history` — per-agent operational telemetry (each LLM call and data_sync,
with records/tokens/status). For last-week agent activity:
`node db_cli.js query meta "SELECT agent, COUNT(*) runs, SUM(records) records, SUM(input_tokens+output_tokens) tokens, MAX(ts) last_run FROM run_history WHERE ts >= datetime('now','-7 days') GROUP BY agent ORDER BY runs DESC"`
Prefer `query` for reads; only `execute` when you must change state, and keep it minimal —
these are live trading records. Example:
`node db_cli.js query app_store "SELECT * FROM trade_ideas WHERE ticker = ?" '["NVDA"]'`

## Committing & pushing (the ONLY allowed git-write path)
When asked to commit/push, use **`./safe-push.sh "message"`** — never run `git commit`,
`git push`, `git reset --hard`, `git rebase`, or any history-rewriting command directly.
`safe-push.sh` enforces the safety rails: it refuses to stage secrets/backups, scans the
diff for API keys, never force-pushes, and pushes only the current branch.
- Preview first with `./safe-push.sh --dry-run` (shows the staged set, writes nothing).
- Push auth from the sandbox needs `GITHUB_TOKEN` in `.env` (a fine-grained PAT with
  contents:write on THIS repo only). Without it, the script commits locally and a push
  must be run from a normal shell.
- Never create branches, tags, or push to anything other than the current branch.

## Verifying changes
Rebuild the dashboard with `node -e "require('./dashboard_agent').buildDashboard()"`.
Tests/validation: `node _validate.js` where applicable.
