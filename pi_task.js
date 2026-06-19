"use strict";
/**
 * pi_task.js — generic Pi runner for this project.
 * Usage: node pi_task.js "your task description here"
 *    or: cat task.txt | node pi_task.js
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
