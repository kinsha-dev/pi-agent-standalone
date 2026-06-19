"use strict";
/**
 * pi_task.js — Claude-Code-driven Pi runner. ⚠️ INTERACTIVE USE ONLY.
 *
 * This is the entry point Claude Code uses to hand a task to pi (directly, or via the
 * /piworkflow command). It runs with { force: true }, which BYPASSES the run controls
 * (dedup / rate-limit / daily run + token caps) in pi_runner.js — appropriate because a
 * human + Claude are supervising each invocation.
 *
 * DO NOT wire this into the autonomous brain, cron, PM2, or any unattended loop: that
 * would let pi run unbounded. The autonomous path is `runPiTask(task, { mode })` in
 * claude_monitor.js, which keeps the controls ON. Keep that boundary.
 *
 * Usage (from a Claude Code Bash step, foreground):
 *   node pi_task.js "your task description here"
 *   cat task.txt | node pi_task.js
 */
require("dotenv").config({ path: require("path").join(__dirname, ".env") });
const { runPiTask } = require("./pi_runner");

const task = process.argv[2] || require("fs").readFileSync("/dev/stdin", "utf8");

if (!task || !task.trim()) {
    console.error("Usage: node pi_task.js \"task description\"");
    process.exit(1);
}

const result = runPiTask(task.trim(), { force: true });
console.log("Pi:", JSON.stringify({ ok: result.ok, skipped: result.skipped, error: result.error, note: result.note }, null, 2));
if (result.output) console.log("\n--- Pi output ---\n" + result.output);
