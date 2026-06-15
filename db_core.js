"use strict";
/**
 * db_core.js — shared SQLite access layer for the trading databases.
 *
 * One implementation, two front-ends:
 *   • mcp_sql_server.mjs — MCP stdio server (for Claude Code and any MCP client)
 *   • db_cli.js          — CLI tool (for the sandboxed `pi` agent, which has no MCP)
 *
 * Uses the builtin `node:sqlite` (Node ≥ 22.5) — no native build, no extra deps.
 *
 * Configuration (all overridable from the environment):
 *   PI_SQL_DATA_DIR     dir holding the .db files   (default: parent of this project)
 *   PI_SQL_APP_STORE_DB explicit path to app_store.db
 *   PI_SQL_MEMORY_DB    explicit path to memory.db
 *   PI_SQL_MODE         "readwrite" (default) | "readonly"  — gates the execute path
 *   PI_SQL_MAX_ROWS     row cap for query results  (default: 1000)
 */
const { DatabaseSync } = require("node:sqlite");
const path = require("path");
const fs   = require("fs");

const DATA_DIR = process.env.PI_SQL_DATA_DIR || path.resolve(__dirname, "..");

// Logical name → absolute file path. Add a database by extending this map.
const DB_PATHS = {
    app_store: process.env.PI_SQL_APP_STORE_DB || path.join(DATA_DIR, "app_store.db"),
    memory:    process.env.PI_SQL_MEMORY_DB    || path.join(DATA_DIR, "memory.db"),
    meta:      process.env.PI_SQL_META_DB      || path.join(DATA_DIR, "meta.db"),
};

const READONLY = (process.env.PI_SQL_MODE || "readwrite").toLowerCase().trim() === "readonly";
const MAX_ROWS = Math.max(1, parseInt(process.env.PI_SQL_MAX_ROWS || "1000", 10) || 1000);

// A valid SQLite identifier we're willing to interpolate into a PRAGMA (which can't
// be parameterized). Anything else is rejected — this is the injection guard.
const IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

function resolveDbPath(name) {
    const p = DB_PATHS[name];
    if (!p) {
        const valid = Object.keys(DB_PATHS).join(", ");
        throw new Error(`unknown database "${name}" — valid: ${valid}`);
    }
    return p;
}

function open(name, { write = false } = {}) {
    const file = resolveDbPath(name);
    if (write && READONLY)
        throw new Error("writes are disabled (PI_SQL_MODE=readonly)");
    if (!write && !fs.existsSync(file))
        throw new Error(`database file not found: ${file}`);
    return new DatabaseSync(file, { readOnly: !write });
}

/** Classify a statement so `query` can refuse anything that mutates. */
function isReadStatement(sql) {
    const s = String(sql).trim().replace(/^\(+/, "").toUpperCase();
    return /^(SELECT|WITH|PRAGMA|EXPLAIN|VALUES)\b/.test(s);
}

/** Normalize bind params: array → positional, plain object → named, undefined → none. */
function bindArgs(params) {
    if (params == null) return [];
    if (Array.isArray(params)) return params;
    if (typeof params === "object") return [params];
    return [params];
}

function listDatabases() {
    return Object.entries(DB_PATHS).map(([name, file]) => {
        let exists = false, sizeBytes = null;
        try { const st = fs.statSync(file); exists = true; sizeBytes = st.size; } catch {}
        return { name, path: file, exists, sizeBytes, mode: READONLY ? "readonly" : "readwrite" };
    });
}

function listTables(name) {
    const db = open(name);
    try {
        return db.prepare(
            "SELECT name, type FROM sqlite_master " +
            "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).all();
    } finally { db.close(); }
}

function describeTable(name, table) {
    if (!IDENT_RE.test(table)) throw new Error(`invalid table name: ${table}`);
    const db = open(name);
    try {
        // Confirm the table exists before interpolating it into PRAGMA statements.
        const exists = db.prepare(
            "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ?"
        ).get(table);
        if (!exists) throw new Error(`no such table/view: ${table}`);
        return {
            table,
            columns:      db.prepare(`PRAGMA table_info(${table})`).all(),
            indexes:      db.prepare(`PRAGMA index_list(${table})`).all(),
            foreign_keys: db.prepare(`PRAGMA foreign_key_list(${table})`).all(),
        };
    } finally { db.close(); }
}

/** Read-only query. Rejects any non-read statement. Caps rows at MAX_ROWS. */
function query(name, sql, params) {
    if (!isReadStatement(sql))
        throw new Error("query() only runs read statements (SELECT/WITH/PRAGMA/EXPLAIN/VALUES). Use execute() to mutate.");
    const db = open(name);
    try {
        const rows = db.prepare(sql).all(...bindArgs(params));
        const truncated = rows.length > MAX_ROWS;
        return { rows: truncated ? rows.slice(0, MAX_ROWS) : rows, rowCount: rows.length, truncated, maxRows: MAX_ROWS };
    } finally { db.close(); }
}

/** Write/DDL. Gated by PI_SQL_MODE. Single statement (use the CLI/SDK once per statement). */
function execute(name, sql, params) {
    const db = open(name, { write: true });
    try {
        const info = db.prepare(sql).run(...bindArgs(params));
        return { changes: Number(info.changes), lastInsertRowid: Number(info.lastInsertRowid) };
    } finally { db.close(); }
}

module.exports = {
    DB_PATHS, READONLY, MAX_ROWS,
    listDatabases, listTables, describeTable, query, execute, isReadStatement,
};
