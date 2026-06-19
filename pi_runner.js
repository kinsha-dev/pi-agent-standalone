"use strict";
/**
 * pi_runner.js — controlled bridge from the AI Brain (claude_monitor) to the
 * sandboxed `pi` coding agent. Three switchable modes via PI_BRAIN_MODE in .env:
 *
 *   off       (default) — the brain may NOT run pi at all. runPiTask() is a no-op.
 *   readonly             — pi runs with the READ tool only (no bash/edit/write):
 *                          analysis/summaries, cannot modify anything.
 *   full                 — pi runs with all tools (read/bash/edit/write), still
 *                          confined to this folder by the Seatbelt sandbox.
 *
 * Every invocation is wrapped in pi-sandbox.sb (filesystem confined to this dir)
 * and uses the brain's Claude model via OpenRouter. Switch modes any time by
 * editing PI_BRAIN_MODE — no code change, takes effect on next brain cycle.
 *
 * PI_LOAD_GRAPH (default "on"): set to "off" to skip injecting the graphify
 * knowledge-graph context into the task prompt. Injecting it costs ~550 tokens
 * but spares pi from blind-reading core files (~158k tokens) to orient itself.
 */
const { spawnSync } = require("child_process");
const path = require("path");
const fs   = require("fs");
const os   = require("os");

// AGENT_DIR = where this agent's own files live (pi binary, sandbox profile, .env, scripts).
// Always __dirname — never overridden.
const AGENT_DIR = __dirname;
const HOME      = os.homedir();

// DIR = the PROJECT being worked on and sandboxed. This agent is meant to be git-cloned
// as a CHILD of the project it edits, so DIR defaults to AGENT_DIR's PARENT. That single
// grant covers both the project AND this nested agent dir (binary/profile/node_modules).
// Override with PI_DIR to point anywhere (e.g. PI_DIR="$AGENT_DIR" to operate on the agent
// repo itself, or an unrelated path). If the parent looks like $HOME or '/', fall back to
// AGENT_DIR so we never sandbox something absurdly broad by accident.
function _defaultProjectDir() {
    if (process.env.PI_DIR) return process.env.PI_DIR;
    const parent = path.resolve(AGENT_DIR, "..");
    if (parent === HOME || parent === "/" || parent === path.dirname(parent)) return AGENT_DIR;
    return parent;
}
const DIR          = _defaultProjectDir();
// Agent's own assets are anchored to AGENT_DIR (they live inside DIR when run as a child).
const SANDBOX_SB   = process.env.PI_SANDBOX_PROFILE || path.join(AGENT_DIR, "pi-sandbox.sb");
const PI_BIN       = process.env.PI_BIN || path.join(AGENT_DIR, "node_modules", ".bin", "pi");
const PI_HOME_DIR  = process.env.PI_HOME_DIR || path.join(HOME, ".pi");
const GITCONFIG    = process.env.PI_GITCONFIG || path.join(HOME, ".gitconfig");
const GITCONFIGDIR = process.env.PI_GITCONFIG_DIR || path.join(HOME, ".config", "git");
const SANDBOX_EXEC = process.env.PI_SANDBOX_EXEC || "/usr/bin/sandbox-exec";

// Optional SQL DBs (read+write via db_cli.js). OFF by default so this agent is
// generic — enable per project by setting PI_SQL_DATA_DIR (or each PI_SQL_*_DB path).
// Only DBs that actually exist on disk are granted into the sandbox; missing ones are
// silently skipped, so a project with no SQLite just runs without the DB layer.
const SQL_DATA_DIR = process.env.PI_SQL_DATA_DIR || "";
function _resolveDb(envVar, fname) {
    const p = process.env[envVar] || (SQL_DATA_DIR ? path.join(SQL_DATA_DIR, fname) : "");
    return (p && fs.existsSync(p)) ? p : "";
}
const SQL_DBS = SQL_DATA_DIR || process.env.PI_SQL_APP_STORE_DB || process.env.PI_SQL_MEMORY_DB || process.env.PI_SQL_META_DB
    ? [
        ["SQLDB_AS",   _resolveDb("PI_SQL_APP_STORE_DB", "app_store.db")],
        ["SQLDB_MEM",  _resolveDb("PI_SQL_MEMORY_DB",    "memory.db")],
        ["SQLDB_META", _resolveDb("PI_SQL_META_DB",      "meta.db")],
      ].filter(([, p]) => p)
    : [];

function piMode() {
    return (process.env.PI_BRAIN_MODE || "off").toLowerCase().trim();
}

const GRAPH_REPORT = path.join(DIR, "graphify-out", "GRAPH_REPORT.md");
const APP_AGENT    = path.join(DIR, "app_agent.md");

/**
 * Load a codebase knowledge-graph context for the pi agent.
 *
 * Prefers `app_agent.md` (the curated, navigable map) when present, since it's
 * richer and already compact. Falls back to extracting the high-signal sections
 * (Summary, God Nodes, Surprising Connections, Hyperedges) from GRAPH_REPORT.md.
 * Returns "" if neither exists. Override with PI_LOAD_GRAPH=off (see runPiTask).
 */
function loadGraphifyContext() {
    // Preferred: the curated map — inject verbatim (already trimmed & organized).
    try {
        const map = fs.readFileSync(APP_AGENT, "utf8").trim();
        if (map) {
            const age = (() => {
                try {
                    const mins = Math.round((Date.now() - fs.statSync(APP_AGENT).mtimeMs) / 60_000);
                    return mins < 60 ? `${mins}m old` : `${Math.round(mins / 60)}h old`;
                } catch { return "age unknown"; }
            })();
            return `=== CODEBASE MAP (app_agent.md, ${age}) ===
Use this map to locate the right file/function before reading anything.
${map}
=== END CODEBASE MAP ===\n\n`;
        }
    } catch { /* no app_agent.md — fall through to the raw report */ }

    let md;
    try { md = fs.readFileSync(GRAPH_REPORT, "utf8"); } catch { return ""; }

    const lines = md.split("\n");
    // Pull these sections only; skip the giant per-community list and nav hubs.
    const WANT = ["## Summary", "## God Nodes", "## Surprising Connections", "## Hyperedges"];
    const out = [];
    let capturing = false;
    for (const line of lines) {
        if (line.startsWith("## ")) {
            capturing = WANT.some(w => line.startsWith(w));
        }
        if (capturing) out.push(line);
    }
    if (!out.length) return "";

    // Dedup repeated lines to save tokens. Strip any leading "N. " list index so
    // identical god-node rows (e.g. five `riskGuards - 22 edges`) collapse to one.
    const seen = new Set();
    const deduped = out.filter(l => {
        const key = l.trim().replace(/^\d+\.\s+/, "");
        if (!key) return true;              // keep blank lines for readability
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
    });

    const age = (() => {
        try {
            const mins = Math.round((Date.now() - fs.statSync(GRAPH_REPORT).mtimeMs) / 60_000);
            return mins < 60 ? `${mins}m old` : `${Math.round(mins / 60)}h old`;
        } catch { return "age unknown"; }
    })();

    return `=== CODEBASE KNOWLEDGE GRAPH (graphify, ${age}) ===
Use this architecture map to locate the right files before reading them.
${deduped.join("\n").trim()}
=== END KNOWLEDGE GRAPH ===\n\n`;
}

// Behavioral preconditions prepended to every pi task. pi runs non-interactively
// (-p, --no-session) so there is no human to answer mid-run questions — any prompt
// for confirmation just stalls the cycle. This preamble tells pi to proceed on
// reasonable assumptions, never block on questions, and keep iterating until the
// change actually runs/verifies clean.
const PI_AUTONOMY_PREAMBLE = `=== OPERATING RULES (non-interactive run — read first) ===
You are running headless with NO human available to answer questions mid-task.
- NEVER ask for confirmation, permission, or clarification. There is no one to reply.
- When something is ambiguous, pick the most reasonable interpretation from the codebase
  conventions and state the assumption in your final summary — then proceed.
- Work token-frugally — this is a metered run:
  • LOCATE before reading. Use the codebase map above and grep to find the exact file and
    line, then read ONLY that range (read with offset+limit). Do not read whole large files,
    and never re-read a file already in your context — you still have its contents.
  • Make the SMALLEST edit that does the job. After editing, verify with the cheapest check
    available (e.g. \`node --check <file>\`, or re-read just the few changed lines). Do NOT
    re-read the entire file to confirm an edit.
  • Bound your effort. If it isn't working after ~3 focused attempts, stop and report what
    you tried and what you observed — do not keep looping.
- Verify before declaring done — quote the command you ran and its output in your summary.
- If a task is genuinely impossible (missing file, missing credential), say so concisely
  and stop — do not loop forever and do not ask a question instead.
=== END OPERATING RULES ===

`;

function _envKey(name) {
    if (process.env[name]) return process.env[name];
    // Look in the AGENT's own .env first, then fall back to the PROJECT's (DIR) — so the
    // key can live in either place (agent self-contained, or shared from the parent project).
    for (const envPath of [path.join(AGENT_DIR, ".env"), path.join(DIR, ".env")]) {
        try {
            const line = fs.readFileSync(envPath, "utf8")
                .split("\n").find(l => l.startsWith(name + "="));
            const v = line ? line.slice(name.length + 1).replace(/^["']|["']$/g, "").trim() : "";
            if (v) return v;
        } catch { /* try next */ }
    }
    return "";
}

// ── Critical-failure hook: ntfy push when pi can't recover from an error ──────────
// OFF unless NTFY_TOPIC is set (env or .env). pi_runner runs OUTSIDE the sandbox, so it
// can reach the ntfy server directly. NTFY_URL defaults to the public ntfy.sh; point it at
// a self-hosted instance to keep alerts private. NTFY_TOKEN is an optional Bearer token for
// protected/self-hosted topics.
const NTFY_TOPIC = _envKey("NTFY_TOPIC");
const NTFY_URL   = (_envKey("NTFY_URL") || "https://ntfy.sh").replace(/\/+$/, "");
const NTFY_TOKEN = _envKey("NTFY_TOKEN");

/** Fire a single ntfy push. Returns false (no-op) when NTFY_TOPIC is unset. Best-effort:
 *  a failed notification never throws into the caller — the run result is what matters. */
function _ntfy(title, body, { priority = "urgent", tags = "rotating_light" } = {}) {
    if (!NTFY_TOPIC) return false;
    const args = [
        "-fsS", "--max-time", "10",
        "-H", `Title: ${title}`,
        "-H", `Priority: ${priority}`,
        "-H", `Tags: ${tags}`,
    ];
    if (NTFY_TOKEN) args.push("-H", `Authorization: Bearer ${NTFY_TOKEN}`);
    args.push("--data-binary", body, `${NTFY_URL}/${NTFY_TOPIC}`);
    try {
        return spawnSync("curl", args, { encoding: "utf8", timeout: 12_000 }).status === 0;
    } catch { return false; }
}

// ── Run controls — stop pi re-running the same issue or burning the token budget ──
// All env-tunable; defaults are conservative for an hourly brain cycle.
const PI_STATE_FILE      = path.join(AGENT_DIR, "pi_run_state.json");  // agent-owned, gitignored here
const PI_DEDUP_WINDOW_MIN = Number(process.env.PI_DEDUP_WINDOW_MIN || 360);   // 6h: same task won't re-run
const PI_MIN_INTERVAL_MIN = Number(process.env.PI_MIN_INTERVAL_MIN || 20);    // ≥20 min between any two runs
const PI_MAX_RUNS_PER_DAY = Number(process.env.PI_MAX_RUNS_PER_DAY || 8);     // hard daily run cap
const PI_DAILY_TOKEN_BUDGET = Number(process.env.PI_DAILY_TOKEN_BUDGET || 250_000); // est. tokens/day cap

function _taskHash(task) {
    const core = String(task).replace(/\s+/g, " ").trim().toLowerCase();
    return require("crypto").createHash("sha1").update(core).digest("hex").slice(0, 16);
}

function _loadPiState() {
    try {
        const s = JSON.parse(fs.readFileSync(PI_STATE_FILE, "utf8"));
        return { runs: Array.isArray(s.runs) ? s.runs : [], day: s.day || "", dayTokens: s.dayTokens || 0, dayCount: s.dayCount || 0 };
    } catch { return { runs: [], day: "", dayTokens: 0, dayCount: 0 }; }
}

function _savePiState(st) {
    try { fs.writeFileSync(PI_STATE_FILE, JSON.stringify(st, null, 2)); } catch (_) {}
}

/** Pre-flight gate: same-issue dedup, min interval, daily run cap, daily token budget. */
function _piGuard(task, mode) {
    const now = Date.now();
    const today = new Date(now).toISOString().slice(0, 10);
    const st = _loadPiState();
    if (st.day !== today) { st.day = today; st.dayTokens = 0; st.dayCount = 0; _savePiState(st); }

    const hash = _taskHash(task);
    const dupe = st.runs.find(r => r.hash === hash && (now - r.ts) < PI_DEDUP_WINDOW_MIN * 60_000);
    if (dupe) {
        const agoMin = Math.round((now - dupe.ts) / 60_000);
        return { ok: false, skipped: true, mode, output: "",
            note: `dedup: same task ran ${agoMin} min ago (window ${PI_DEDUP_WINDOW_MIN}min). Set PI_FORCE=1 to override.` };
    }
    const last = st.runs[st.runs.length - 1];
    if (last && (now - last.ts) < PI_MIN_INTERVAL_MIN * 60_000) {
        const waitMin = Math.ceil((PI_MIN_INTERVAL_MIN * 60_000 - (now - last.ts)) / 60_000);
        return { ok: false, skipped: true, mode, output: "",
            note: `rate-limit: last pi run <${PI_MIN_INTERVAL_MIN}min ago, wait ~${waitMin} min` };
    }
    if (st.dayCount >= PI_MAX_RUNS_PER_DAY)
        return { ok: false, skipped: true, mode, output: "",
            note: `daily cap: ${st.dayCount}/${PI_MAX_RUNS_PER_DAY} pi runs used today` };
    if (st.dayTokens >= PI_DAILY_TOKEN_BUDGET)
        return { ok: false, skipped: true, mode, output: "",
            note: `token budget: ~${st.dayTokens}/${PI_DAILY_TOKEN_BUDGET} est. tokens used today` };
    return null; // clear to run
}

function _recordPiRun(task, estTokens) {
    const now = Date.now();
    const today = new Date(now).toISOString().slice(0, 10);
    const st = _loadPiState();
    if (st.day !== today) { st.day = today; st.dayTokens = 0; st.dayCount = 0; }
    st.runs.push({ ts: now, hash: _taskHash(task), tokensEst: estTokens });
    if (st.runs.length > 50) st.runs = st.runs.slice(-50);
    st.dayTokens += estTokens;
    st.dayCount  += 1;
    _savePiState(st);
}

/**
 * Run a one-shot task through the sandboxed pi agent, gated by PI_BRAIN_MODE.
 * @returns {{ok:boolean, mode:string, skipped?:boolean, output:string, error?:string, note?:string}}
 */
function runPiTask(task, opts = {}) {
    const mode = (opts.mode || piMode());

    if (mode === "off")
        return { ok: false, skipped: true, mode, output: "", note: "PI_BRAIN_MODE=off — brain may not run pi" };

    // Run controls (dedup / rate-limit / daily caps). PI_FORCE=1 or opts.force bypasses.
    if (!opts.force && (process.env.PI_FORCE || "").trim() !== "1") {
        const blocked = _piGuard(task, mode);
        if (blocked) return blocked;
    }

    if (!fs.existsSync(PI_BIN))
        return { ok: false, mode, output: "", error: "pi not installed (run: npm i @earendil-works/pi-coding-agent)" };
    // Seatbelt (sandbox-exec) only exists on macOS. On Linux (e.g. inside the Docker image)
    // the container itself is the isolation boundary, so pi runs unwrapped there — see the
    // platform branch around the spawnSync call below.
    const useSeatbelt = process.platform === "darwin";
    if (useSeatbelt && (!fs.existsSync(SANDBOX_SB) || !fs.existsSync(SANDBOX_EXEC)))
        return { ok: false, mode, output: "", error: "sandbox profile or sandbox-exec missing" };

    // Tool policy per mode. readonly = the `read` tool only → cannot mutate anything.
    const toolArgs = mode === "readonly" ? ["--tools", "read"] : [];
    const provider = process.env.PI_PROVIDER || "openrouter";
    const model    = process.env.PI_MODEL    || "deepseek/deepseek-v4-flash";
    // Reasoning budget. Defaults to "low": small mechanical edits don't need long thinking
    // traces, which are a major token sink. Dial up (medium/high) for genuinely hard tasks,
    // or "off" for the cheapest runs. Levels: off|minimal|low|medium|high|xhigh.
    const thinking = process.env.PI_THINKING || "low";

    const env = { ...process.env, OPENROUTER_API_KEY: _envKey("OPENROUTER_API_KEY") };

    // Force-load the knowledge-graph context unless the caller opts out (opts.loadGraph=false)
    // or it's globally disabled via PI_LOAD_GRAPH=off in .env. Grounds the pi agent in the
    // codebase architecture (~550 tok) instead of blind-reading core files (~158k tok) to orient.
    const graphEnabled = opts.loadGraph !== false
        && (process.env.PI_LOAD_GRAPH || "on").toLowerCase().trim() !== "off";
    const graphCtx = graphEnabled ? loadGraphifyContext() : "";
    const graphTokens = Math.round(graphCtx.length / 4);  // ~4 chars/token, matches brain heuristic
    // Order: operating rules → architecture map → the task itself.
    const fullTask = PI_AUTONOMY_PREAMBLE + graphCtx + task;

    // The sandbox profile references SQLDB_AS/MEM/META params, so all three must be
    // defined. Missing DBs point at /dev/null (granting it is a harmless no-op).
    const sqlMap = { SQLDB_AS: "/dev/null", SQLDB_MEM: "/dev/null", SQLDB_META: "/dev/null" };
    for (const [k, p] of SQL_DBS) sqlMap[k] = p;

    const piArgs = [
        "--provider", provider, "--model", model,
        "--thinking", thinking,
        "--no-session", "--mode", "text", ...toolArgs,
        "-p", fullTask,
    ];

    // macOS: wrap in Seatbelt (sandbox-exec) for filesystem/network confinement.
    // Linux (Docker): no sandbox-exec available — spawn pi directly. The Docker container
    // is the isolation boundary there instead.
    const res = useSeatbelt
        ? spawnSync(SANDBOX_EXEC, [
              "-D", `DIR=${DIR}`,
              "-D", `PIHOME=${PI_HOME_DIR}`,
              "-D", `GITCONFIG=${GITCONFIG}`,
              "-D", `GITCONFIGDIR=${GITCONFIGDIR}`,
              "-D", `SQLDB_AS=${sqlMap.SQLDB_AS}`,
              "-D", `SQLDB_MEM=${sqlMap.SQLDB_MEM}`,
              "-D", `SQLDB_META=${sqlMap.SQLDB_META}`,
              "-f", SANDBOX_SB,
              PI_BIN, ...piArgs,
          ], {
              cwd: DIR, encoding: "utf8",
              timeout: opts.timeout || 300_000, maxBuffer: 20_000_000, env,
          })
        : spawnSync(PI_BIN, piArgs, {
              cwd: DIR, encoding: "utf8",
              timeout: opts.timeout || 300_000, maxBuffer: 20_000_000, env,
          });

    const output = (res.stdout || "").trim();
    // Estimate total tokens: injected prompt + model output (~4 chars/token).
    const estTokens = Math.round((fullTask.length + output.length) / 4);
    _recordPiRun(task, estTokens);
    const st = _loadPiState();

    // Critical-failure hook: pi exited non-zero / timed out → it could NOT recover the app.
    // Push an ntfy alert so a human knows it's still broken. Opt-in via NTFY_TOPIC; the
    // dedup guard above means a repeating failure won't re-alert within the window. Callers
    // can force a push on a clean-but-unresolved run with opts.notify=true, or mute with false.
    const runFailed = res.status !== 0;
    const shouldNotify = opts.notify !== false && (opts.notify === true || runFailed);
    if (shouldNotify) {
        const reason = runFailed
            ? (String(res.stderr || "").replace(/\s+/g, " ").trim().slice(0, 200) || `exit ${res.status}`)
            : "run completed but flagged unresolved by caller";
        _ntfy("pi agent: unrecovered critical error",
            `Task: ${String(task).replace(/\s+/g, " ").trim().slice(0, 160)}\n` +
            `Dir: ${DIR}\nMode: ${mode}\nReason: ${reason}\n` +
            `Today: ${st.dayCount} runs / ~${st.dayTokens} est. tokens`,
            { priority: "urgent", tags: "rotating_light,warning" });
    }

    return {
        ok:        res.status === 0,
        mode,
        graphLoaded: !!graphCtx,
        graphTokens,
        estTokens,
        dayTokens: st.dayTokens,
        dayCount:  st.dayCount,
        output,
        error:     res.status === 0 ? null : (String(res.stderr || "").slice(0, 300) || `exit ${res.status}`),
    };
}

module.exports = { runPiTask, piMode, loadGraphifyContext };
