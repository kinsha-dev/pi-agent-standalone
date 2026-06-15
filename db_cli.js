#!/usr/bin/env node
"use strict";
/**
 * db_cli.js — command-line front-end over db_core.js for the sandboxed `pi` agent.
 *
 * pi has no MCP support (by design), so it queries the trading SQLite DBs by shelling
 * out to this tool. All output is JSON on stdout; errors are JSON on stderr + exit 1.
 *
 * Usage:
 *   node db_cli.js databases
 *   node db_cli.js tables   <db>
 *   node db_cli.js schema   <db> <table>
 *   node db_cli.js query    <db> "<SELECT ...>" ['[json,params]']
 *   node db_cli.js execute  <db> "<INSERT/UPDATE/... >" ['[json,params]']     # needs PI_SQL_MODE=readwrite
 *
 *   <db> is one of: app_store | memory
 *
 * Examples:
 *   node db_cli.js tables app_store
 *   node db_cli.js query memory "SELECT session_ts, ndx_signal FROM sessions ORDER BY id DESC LIMIT 5"
 *   node db_cli.js query app_store "SELECT * FROM trade_ideas WHERE ticker = ?" '["NVDA"]'
 */
const core = require("./db_core");

function out(obj) { process.stdout.write(JSON.stringify(obj, null, 2) + "\n"); }
function fail(msg) { process.stderr.write(JSON.stringify({ ok: false, error: String(msg) }) + "\n"); process.exit(1); }

function parseParams(raw) {
    if (raw == null) return undefined;
    try { return JSON.parse(raw); }
    catch { throw new Error(`params must be valid JSON (array or object), got: ${raw}`); }
}

function main() {
    const [cmd, db, a, b] = process.argv.slice(2);
    try {
        switch ((cmd || "").toLowerCase()) {
            case "databases":
            case "dbs":
                return out({ ok: true, databases: core.listDatabases() });
            case "tables":
                if (!db) throw new Error("usage: db_cli.js tables <db>");
                return out({ ok: true, db, tables: core.listTables(db) });
            case "schema":
            case "describe":
                if (!db || !a) throw new Error("usage: db_cli.js schema <db> <table>");
                return out({ ok: true, db, ...core.describeTable(db, a) });
            case "query":
                if (!db || !a) throw new Error('usage: db_cli.js query <db> "<SELECT ...>" [params-json]');
                return out({ ok: true, db, ...core.query(db, a, parseParams(b)) });
            case "execute":
            case "exec":
                if (!db || !a) throw new Error('usage: db_cli.js execute <db> "<SQL>" [params-json]');
                return out({ ok: true, db, ...core.execute(db, a, parseParams(b)) });
            default:
                throw new Error("commands: databases | tables <db> | schema <db> <table> | query <db> <sql> [params] | execute <db> <sql> [params]");
        }
    } catch (e) { fail(e.message || e); }
}

main();
