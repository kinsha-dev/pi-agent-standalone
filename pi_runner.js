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

// Every dynamic path is overridable from the environment so this runner is portable
// across machines/users. Defaults derive from __dirname and the home dir, matching
// pi-sandboxed.sh. Set PI_DIR / PI_HOME_DIR / PM2_HOME / PI_GITCONFIG[_DIR] /
// PI_BIN / PI_SANDBOX_PROFILE to override.
const DIR          = process.env.PI_DIR || __dirname;
const HOME         = os.homedir();
const SANDBOX_SB   = process.env.PI_SANDBOX_PROFILE || path.join(DIR, "pi-sandbox.sb");
const PI_BIN       = process.env.PI_BIN || path.join(DIR, "node_modules", ".bin", "pi");
const PI_HOME_DIR  = process.env.PI_HOME_DIR || path.join(HOME, ".pi");
const GITCONFIG    = process.env.PI_GITCONFIG || path.join(HOME, ".gitconfig");
const GITCONFIGDIR = process.env.PI_GITCONFIG_DIR || path.join(HOME, ".config", "git");
const SANDBOX_EXEC = process.env.PI_SANDBOX_EXEC || "/usr/bin/sandbox-exec";

function piMode() {
    return (process.env.PI_BRAIN_MODE || "off").toLowerCase().trim();
}

const GRAPH_REPORT = path.join(DIR, "graphify-out", "GRAPH_REPORT.md");

/**
 * Load a compact codebase knowledge-graph context from graphify-out/GRAPH_REPORT.md.
 * Extracts only the high-signal, token-cheap sections (Summary, God Nodes,
 * Surprising Connections, Hyperedges) so the pi agent starts grounded in the
 * actual architecture instead of blind-reading files. Returns "" if no graph exists.
 */
function loadGraphifyContext() {
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
- Do not stop at the first error. Iterate: read the failing file, apply a fix, re-run
  the relevant check (e.g. \`node --check <file>\`, the agent's own command), and repeat
  until it runs correctly or you have exhausted reasonable attempts.
- Prefer the smallest change that makes it work. Verify before declaring done — quote the
  command you ran and its output in your summary.
- If a task is genuinely impossible (missing file, missing credential), say so concisely
  and stop — do not loop forever and do not ask a question instead.
=== END OPERATING RULES ===

`;

function _envKey(name) {
    if (process.env[name]) return process.env[name];
    try {
        const line = fs.readFileSync(path.join(DIR, ".env"), "utf8")
            .split("\n").find(l => l.startsWith(name + "="));
        return line ? line.slice(name.length + 1).replace(/^["']|["']$/g, "").trim() : "";
    } catch { return ""; }
}

/**
 * Run a one-shot task through the sandboxed pi agent, gated by PI_BRAIN_MODE.
 * @returns {{ok:boolean, mode:string, skipped?:boolean, output:string, error?:string, note?:string}}
 */
function runPiTask(task, opts = {}) {
    const mode = (opts.mode || piMode());

    if (mode === "off")
        return { ok: false, skipped: true, mode, output: "", note: "PI_BRAIN_MODE=off — brain may not run pi" };

    if (!fs.existsSync(PI_BIN))
        return { ok: false, mode, output: "", error: "pi not installed (run: npm i @earendil-works/pi-coding-agent)" };
    if (!fs.existsSync(SANDBOX_SB) || !fs.existsSync(SANDBOX_EXEC))
        return { ok: false, mode, output: "", error: "sandbox profile or sandbox-exec missing" };

    // Tool policy per mode. readonly = the `read` tool only → cannot mutate anything.
    const toolArgs = mode === "readonly" ? ["--tools", "read"] : [];
    const provider = process.env.PI_PROVIDER || "openrouter";
    // v3.1 tool-calls reliably; v3-0324 narrated actions instead of executing them.
    const model    = process.env.PI_MODEL    || "deepseek/deepseek-chat-v3.1";

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

    const args = [
        "-D", `DIR=${DIR}`,
        "-D", `PIHOME=${PI_HOME_DIR}`,
        "-D", `GITCONFIG=${GITCONFIG}`,
        "-D", `GITCONFIGDIR=${GITCONFIGDIR}`,
        "-f", SANDBOX_SB,
        PI_BIN, "--provider", provider, "--model", model,
        "--no-session", "--mode", "text", ...toolArgs,
        "-p", fullTask,
    ];

    const res = spawnSync(SANDBOX_EXEC, args, {
        cwd: DIR, encoding: "utf8",
        timeout: opts.timeout || 300_000, maxBuffer: 20_000_000, env,
    });

    return {
        ok:        res.status === 0,
        mode,
        graphLoaded: !!graphCtx,
        graphTokens,
        output:    (res.stdout || "").trim(),
        error:     res.status === 0 ? null : (String(res.stderr || "").slice(0, 300) || `exit ${res.status}`),
    };
}

module.exports = { runPiTask, piMode, loadGraphifyContext };
