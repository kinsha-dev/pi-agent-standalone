#!/usr/bin/env node
"use strict";
/**
 * mcp_sql_server.js — Model Context Protocol (stdio) server exposing the trading
 * SQLite databases (app_store.db, memory.db) to any MCP client (e.g. Claude Code).
 *
 * pi does NOT use this — pi has no MCP and shells out to db_cli.js instead. Both
 * front-ends share db_core.js, so behavior (DB map, read/write gating, row caps,
 * injection guards) is identical regardless of caller.
 *
 * Transport: stdio. JSON-RPC travels on stdout; logs/warnings go to stderr only,
 * so node:sqlite's experimental warning can't corrupt the protocol stream.
 *
 * Wire into Claude Code via .mcp.json (see that file).
 */
const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { ListToolsRequestSchema, CallToolRequestSchema } = require("@modelcontextprotocol/sdk/types.js");
const core = require("./db_core");

const DB_ENUM = Object.keys(core.DB_PATHS);

const TOOLS = [
    {
        name: "list_databases",
        description: "List the available trading databases (logical name, file path, size, mode).",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
        name: "list_tables",
        description: "List tables and views in a database.",
        inputSchema: {
            type: "object",
            properties: { database: { type: "string", enum: DB_ENUM, description: "which database" } },
            required: ["database"], additionalProperties: false,
        },
    },
    {
        name: "describe_table",
        description: "Return columns, indexes and foreign keys for a table/view.",
        inputSchema: {
            type: "object",
            properties: {
                database: { type: "string", enum: DB_ENUM },
                table: { type: "string", description: "table or view name" },
            },
            required: ["database", "table"], additionalProperties: false,
        },
    },
    {
        name: "query",
        description: "Run a READ-ONLY SQL statement (SELECT/WITH/PRAGMA/EXPLAIN/VALUES). " +
            "Use ? placeholders with params for safe binding. Results are capped at PI_SQL_MAX_ROWS.",
        inputSchema: {
            type: "object",
            properties: {
                database: { type: "string", enum: DB_ENUM },
                sql: { type: "string", description: "a single read-only SQL statement" },
                params: { type: "array", description: "positional bind values for ? placeholders", items: {} },
            },
            required: ["database", "sql"], additionalProperties: false,
        },
    },
    {
        name: "execute",
        description: "Run a single writing/DDL statement (INSERT/UPDATE/DELETE/CREATE/...). " +
            "Disabled when the server runs in readonly mode (PI_SQL_MODE=readonly). Returns rows changed.",
        inputSchema: {
            type: "object",
            properties: {
                database: { type: "string", enum: DB_ENUM },
                sql: { type: "string", description: "a single writing SQL statement" },
                params: { type: "array", description: "positional bind values for ? placeholders", items: {} },
            },
            required: ["database", "sql"], additionalProperties: false,
        },
    },
];

const server = new Server(
    { name: "trading-sql", version: "1.0.0" },
    { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const { name, arguments: args = {} } = req.params;
    try {
        let result;
        switch (name) {
            case "list_databases": result = core.listDatabases(); break;
            case "list_tables":    result = core.listTables(args.database); break;
            case "describe_table": result = core.describeTable(args.database, args.table); break;
            case "query":          result = core.query(args.database, args.sql, args.params); break;
            case "execute":        result = core.execute(args.database, args.sql, args.params); break;
            default: throw new Error(`unknown tool: ${name}`);
        }
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    } catch (e) {
        return { isError: true, content: [{ type: "text", text: `Error: ${e.message || e}` }] };
    }
});

async function main() {
    await server.connect(new StdioServerTransport());
    // Banner on stderr only — never stdout (that's the JSON-RPC channel).
    process.stderr.write(`trading-sql MCP server ready — mode=${core.READONLY ? "readonly" : "readwrite"}, dbs=[${DB_ENUM.join(", ")}]\n`);
}

main().catch((e) => { process.stderr.write(`fatal: ${e.stack || e}\n`); process.exit(1); });
