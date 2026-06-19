#!/usr/bin/env bash
# setup.sh — bootstrap the sandboxed pi agent against any project.
#
#   ./scripts/setup.sh [TARGET_DIR]
#
# TARGET_DIR defaults to $PI_DIR, then the current directory. Steps (each is safe to
# re-run and skips what's already present):
#   1. install agent deps (npm i) in this repo
#   2. ensure the target has an AGENTS.md (writes a generic starter if missing)
#   3. build the graphify codebase map if the CLI is available (optional)
#   4. install the post-commit hook pipeline (graph + app_agent.md)
#
# Nothing here is project-specific. The SQL-DB layer stays OFF unless you set
# PI_SQL_DATA_DIR. Set keys in .env (OPENROUTER_API_KEY) before running pi.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SELF_DIR/.." && pwd)"
TARGET="${1:-${PI_DIR:-$(pwd)}}"
TARGET="$(cd "$TARGET" && pwd)"

echo "── pi-agent setup ──"
echo "agent:  $AGENT_DIR"
echo "target: $TARGET"
echo

# 1. deps
if [ ! -d "$AGENT_DIR/node_modules/.bin" ] || [ ! -x "$AGENT_DIR/node_modules/.bin/pi" ]; then
  echo "→ installing agent dependencies…"
  ( cd "$AGENT_DIR" && npm install --no-audit --no-fund )
else
  echo "✓ deps present"
fi

# 1b. pi-subagents extension — required by /piworkflow and pi_task.js orchestration
# (worker/reviewer delegation). Published on npm; idempotent if already installed.
PI="$AGENT_DIR/node_modules/.bin/pi"
if [ -x "$PI" ]; then
  if "$PI" list 2>/dev/null | grep -qi "pi-subagents"; then
    echo "✓ pi-subagents extension present"
  else
    echo "→ installing pi-subagents extension (npm:pi-subagents)…"
    ( cd "$AGENT_DIR" && "$PI" install npm:pi-subagents ) \
      && echo "✓ pi-subagents installed" \
      || echo "⚠️  'pi install npm:pi-subagents' failed — /piworkflow needs it; install manually later"
  fi
else
  echo "⚠️  pi binary not found at $PI — skipping pi-subagents (run npm install first)"
fi

# 2. starter AGENTS.md in the target (pi reads this as its instructions)
if [ -f "$TARGET/AGENTS.md" ]; then
  echo "✓ target already has AGENTS.md"
else
  echo "→ writing a generic starter AGENTS.md to the target"
  cat > "$TARGET/AGENTS.md" <<'AG'
# Pi agent context

You are the `pi` coding agent running **sandboxed inside this project folder only**.
You cannot read or write outside this directory — do not try.

## Operating mode (read first)
You run autonomously. Assume **no human is watching to answer questions.**
- **Do not ask for confirmation, permission, or clarification.** Decide and act.
- When ambiguous, choose the most reasonable option from this project's conventions,
  note the assumption in your final summary, and proceed.
- **Iterate until it works.** Don't stop at the first error: read the failing file, fix,
  re-run the check, repeat until it runs clean — or you've made several honest attempts.
- Make the smallest change that works. **Verify before declaring done** — run the command
  and quote its output.
- Only stop early if genuinely blocked (missing file/credential): say so briefly and stop.

## Codebase map — `app_agent.md`
If `app_agent.md` exists it is injected into your task automatically. Use it to jump to
the right file instead of blind-reading. Regenerate it with `/graphify . --update`.

## How to work here
- Match the surrounding code style.
- TODO: add this project's build/test/verify commands and any guardrails here.
AG
  echo "  ✎ edit $TARGET/AGENTS.md to add project-specific build/test commands."
fi

# 3. graphify map (optional)
if command -v graphify >/dev/null 2>&1; then
  if [ ! -f "$TARGET/graphify-out/graph.json" ]; then
    echo "→ building graphify codebase map (one-time)…"
    ( cd "$TARGET" && graphify . --no-viz ) || echo "⚠️  graphify build skipped/failed — continue without the map"
  else
    echo "✓ graphify map already built"
  fi
  # generate the first app_agent.md
  PY=$(cat "$TARGET/graphify-out/.graphify_python" 2>/dev/null || command -v python3)
  [ -x "$PY" ] && "$PY" "$AGENT_DIR/scripts/gen_app_agent.py" "$TARGET" || true
else
  echo "⚠️  'graphify' CLI not found — skipping the codebase map (pi still runs, just without it)."
fi

# 4. hooks
echo "→ installing commit-hook pipeline…"
"$SELF_DIR/install-hooks.sh" "$TARGET"

echo
echo "✅ setup complete. Run the agent against this target with:"
echo "     PI_DIR=\"$TARGET\" \"$AGENT_DIR/pi-sandboxed.sh\" -p \"your task\""
echo "   or set OPENROUTER_API_KEY in $AGENT_DIR/.env first."
