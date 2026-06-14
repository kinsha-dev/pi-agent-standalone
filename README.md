# pi-Agent: Sandboxed AI Coding Assistant for any project

**pi-Agent** is a secure, sandboxed AI coding assistant that integrates with the `pi` CLI tool to provide autonomous code modification capabilities within a app platform. It enables the AI brain (`app_monitor.js`) to execute code changes, file edits, and system operations safely within a confined environment.


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

## Installation

```bash
# Clone the repository
git clone https://github.com/kinsha-dev/pi-agent.git
cd pi-agent

# Install dependencies
npm install @earendil-works/pi-coding-agent

# Install pi CLI globally (if not already installed)
npm install -g @earendil-works/pi
```

## Configuration

Set environment variables in `.env`:

```bash
# Required for pi agent operation
OPENROUTER_API_KEY=sk-or-v1-...
PI_BRAIN_MODE=full              # off | readonly | full
PI_MODEL=deepseek/deepseek-chat-v3.1
PI_PROVIDER=openrouter
PI_LOAD_GRAPH=on                # Inject knowledge graph context

# Optional: Deployment tokens
NETLIFY_TOKEN=...
GITHUB_TOKEN=...
```

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

The sandbox profile enforces:
- Read/write access only within the project directory
- No network access (deny network*)
- No process execution outside the sandbox
- No system-level modifications
- Denied file operations: `file-write*`, `file-read-data`, `file-read-metadata`

## Knowledge Graph Integration

When `PI_LOAD_GRAPH=on`, the agent injects a compact knowledge graph containing:
- Project architecture summary
- Key "god node" files and their purposes
- Surprising connections between modules
- Hyperedges (cross-cutting concerns)

This provides ~550 tokens of context vs. ~158k tokens for blind file reading.

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

1. **Filesystem confinement** – Cannot access files outside project
2. **No network** – Cannot make external calls or exfiltrate data
3. **Tool restrictions** – `readonly` mode for analysis only
4. **Git safety** – Uses safe push scripts with API key detection
5. **Secrets protection** – `.env` files are gitignored and blocked from commits

## Files

- `pi_runner.js` – Main bridge module
- `pi-sandboxed.sh` – Sandbox execution wrapper
- `pi-sandbox.sb` – macOS Seatbelt sandbox profile
- `AGENTS.md` – Operating context and guidelines
- `package.json` – Dependencies

## License

MIT
