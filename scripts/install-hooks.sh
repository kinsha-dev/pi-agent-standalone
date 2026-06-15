#!/usr/bin/env bash
# install-hooks.sh — wire the graphify knowledge-graph pipeline into a project's git
# hooks so the codebase map (graph.json + GRAPH_REPORT.md + app_agent.md) stays fresh.
#
#   ./scripts/install-hooks.sh [TARGET_DIR]
#
# TARGET_DIR defaults to $PI_DIR, then the current directory. It must be a git repo.
# Idempotent: re-running updates the appended block in place.
#
# What it installs into TARGET_DIR/.git/hooks/post-commit:
#   1. graphify's own rebuild (via `graphify hook install`) — graph.json/report, code-only,
#      backgrounded, no LLM. Skipped if the `graphify` CLI isn't found (prints a hint).
#   2. an app_agent.md regeneration step (scripts/gen_app_agent.py) that runs after the
#      graph rebuild so the map reflects the new graph.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../scripts
AGENT_DIR="$(cd "$SELF_DIR/.." && pwd)"                        # the pi-agent repo
TARGET="${1:-${PI_DIR:-$(pwd)}}"
TARGET="$(cd "$TARGET" && pwd)"

GITDIR="$TARGET/.git"
[ -d "$GITDIR" ] || { echo "❌ $TARGET is not a git repo (.git not found)" >&2; exit 1; }
HOOK="$GITDIR/hooks/post-commit"
mkdir -p "$GITDIR/hooks"

echo "→ target project: $TARGET"

# 1. graphify's own hook (graph.json + GRAPH_REPORT.md). Optional — needs the CLI.
if command -v graphify >/dev/null 2>&1; then
  ( cd "$TARGET" && graphify hook install >/dev/null 2>&1 ) \
    && echo "✓ graphify graph-rebuild hook installed" \
    || echo "⚠️  graphify hook install failed (run '/graphify .' once, then re-run this)"
else
  echo "⚠️  'graphify' CLI not found — graph rebuild step skipped."
  echo "    Install it (pip/uv install graphifyy) and re-run, or build the graph manually."
fi

# 2. Append the app_agent.md regeneration step (idempotent — replace any prior block).
MARKER_START="# pi-agent app_agent regen start"
MARKER_END="# pi-agent app_agent regen end"
if [ -f "$HOOK" ]; then
  # strip a previous block if present
  /usr/bin/sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOOK" 2>/dev/null || \
    sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOOK" 2>/dev/null || true
else
  printf '#!/bin/sh\n' > "$HOOK"
fi

cat >> "$HOOK" <<EOF
$MARKER_START
# Regenerate app_agent.md from the (freshly rebuilt) graph. Detached + delayed so it
# picks up graphify's background rebuild. Never blocks the commit.
( sleep 20
  _PY=""
  [ -f "$TARGET/graphify-out/.graphify_python" ] && _PY=\$(cat "$TARGET/graphify-out/.graphify_python" 2>/dev/null)
  [ -x "\$_PY" ] || _PY=\$(command -v python3 2>/dev/null)
  [ -x "\$_PY" ] && "\$_PY" "$AGENT_DIR/scripts/gen_app_agent.py" "$TARGET" >> "\${HOME}/.cache/graphify-rebuild.log" 2>&1
) >/dev/null 2>&1 &
$MARKER_END
EOF

chmod +x "$HOOK"
echo "✓ app_agent.md regeneration wired into $HOOK"
echo "Done. Every commit in $TARGET now refreshes the graph + app_agent.md."
