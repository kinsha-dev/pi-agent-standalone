#!/usr/bin/env bash
# pi-sandboxed.sh — run the `pi` coding agent CONFINED to this project folder,
# wired to the same Claude model the AI Brain uses (via the project's OpenRouter key).
#
#   ./pi-sandboxed.sh                     # interactive, sandboxed
#   ./pi-sandboxed.sh -p "list the agents"   # one-shot
#
# Filesystem confinement is enforced by macOS Seatbelt (pi-sandbox.sb): pi can read
# the OS runtime + this folder, but can only WRITE inside this folder, and cannot
# read other user folders. Network stays open so the LLM API works.
#
# This agent is meant to be git-cloned as a CHILD of the project it edits. So the
# SANDBOXED PROJECT (DIR) defaults to the PARENT of this script's dir, while the agent's
# own assets (pi binary, profile, .env) come from AGENT_DIR. One grant of DIR covers both.
#   PI_DIR              project to sandbox           (default: PARENT of the agent dir)
#   PI_HOME_DIR         pi runtime dir               (default: $HOME/.pi)
#   PI_GITCONFIG[_DIR]  git config file/dir          (default: $HOME/.gitconfig, ~/.config/git)
#   PI_BIN              pi binary                     (default: AGENT_DIR/node_modules/.bin/pi)
#   PI_SANDBOX_PROFILE  seatbelt profile             (default: AGENT_DIR/pi-sandbox.sb)
#   PI_ENV_FILE         .env to read keys from        (default: AGENT_DIR/.env)
#   PI_PROVIDER / PI_MODEL / PI_THINKING             (LLM provider / model / reasoning)
set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the agent's own files

# Sandboxed project = parent of the agent dir (child-clone layout), overridable with PI_DIR.
# Guard against sandboxing $HOME or '/' if the agent is checked out somewhere shallow.
if [ -n "${PI_DIR:-}" ]; then
  DIR="$PI_DIR"
else
  _parent="$(cd "$AGENT_DIR/.." && pwd)"
  if [ "$_parent" = "$HOME" ] || [ "$_parent" = "/" ]; then DIR="$AGENT_DIR"; else DIR="$_parent"; fi
fi

# Dynamic paths — all overridable from bash.
PI_HOME_DIR="${PI_HOME_DIR:-$HOME/.pi}"
GITCONFIG="${PI_GITCONFIG:-$HOME/.gitconfig}"
GITCONFIGDIR="${PI_GITCONFIG_DIR:-$HOME/.config/git}"

# Optional SQL DBs (read+write by db_cli.js). OFF by default so this agent is generic —
# enable per project by setting PI_SQL_DATA_DIR (or each PI_SQL_*_DB path). Only DBs that
# exist on disk are granted into the sandbox; the rest point at /dev/null (a harmless
# no-op grant), so a project with no SQLite just runs without the DB layer.
_db() { [ -n "$1" ] && [ -e "$1" ] && echo "$1" || echo "/dev/null"; }
if [ -n "${PI_SQL_DATA_DIR:-}${PI_SQL_APP_STORE_DB:-}${PI_SQL_MEMORY_DB:-}${PI_SQL_META_DB:-}" ]; then
  SQL_DATA_DIR="${PI_SQL_DATA_DIR:-}"
  SQLDB_AS="$(_db "${PI_SQL_APP_STORE_DB:-${SQL_DATA_DIR:+$SQL_DATA_DIR/app_store.db}}")"
  SQLDB_MEM="$(_db "${PI_SQL_MEMORY_DB:-${SQL_DATA_DIR:+$SQL_DATA_DIR/memory.db}}")"
  SQLDB_META="$(_db "${PI_SQL_META_DB:-${SQL_DATA_DIR:+$SQL_DATA_DIR/meta.db}}")"
else
  SQLDB_AS="/dev/null"; SQLDB_MEM="/dev/null"; SQLDB_META="/dev/null"
fi
export SQLDB_AS SQLDB_MEM SQLDB_META
PI_BIN="${PI_BIN:-$AGENT_DIR/node_modules/.bin/pi}"
SANDBOX_PROFILE="${PI_SANDBOX_PROFILE:-$AGENT_DIR/pi-sandbox.sb}"
ENV_FILE="${PI_ENV_FILE:-$AGENT_DIR/.env}"

# Pull keys from the AGENT's .env first, then fall back to the PROJECT's (DIR) .env, so the
# key can live in either (the file has comments/parens that break `source`).
envval() {
  for f in "$ENV_FILE" "$DIR/.env"; do
    v=$(grep -E "^$1=" "$f" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'"'"']//;s/["'"'"']$//')
    [ -n "$v" ] && { echo "$v"; return; }
  done
}
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(envval OPENROUTER_API_KEY)}"
export GEMINI_API_KEY="${GEMINI_API_KEY:-$(envval GEMINI_API_KEY)}"

# Backend: OpenRouter DeepSeek V3.1 (override with PI_MODEL / PI_PROVIDER)
PROVIDER="${PI_PROVIDER:-openrouter}"
MODEL="${PI_MODEL:-deepseek/deepseek-chat-v3.1}"   # v3.1 tool-calls reliably (v4-flash/v3-0324 narrate)
# Reasoning budget — "low" keeps small edits cheap; bump to medium/high for hard tasks,
# or "off" for the cheapest runs (off|minimal|low|medium|high|xhigh).
THINKING="${PI_THINKING:-low}"

# Fail fast on a misconfigured path rather than a cryptic sandbox error.
[ -f "$PI_BIN" ] || { echo "❌ pi binary not found: $PI_BIN (set PI_BIN)" >&2; exit 1; }

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "⚠️  OPENROUTER_API_KEY not set ($ENV_FILE) — pi can't reach the Claude model." >&2
fi

# Run from the project dir so pi reads the project's AGENTS.md / app_agent.md (not the agent's).
cd "$DIR"

# Seatbelt (sandbox-exec) only exists on macOS. On Linux (e.g. inside the Docker image) the
# container itself is the isolation boundary, so pi runs unwrapped there instead.
if [ "$(uname)" = "Darwin" ]; then
  [ -f "$SANDBOX_PROFILE" ] || { echo "❌ sandbox profile not found: $SANDBOX_PROFILE (set PI_SANDBOX_PROFILE)" >&2; exit 1; }
  exec sandbox-exec \
    -D "DIR=$DIR" \
    -D "PIHOME=$PI_HOME_DIR" \
    -D "GITCONFIG=$GITCONFIG" \
    -D "GITCONFIGDIR=$GITCONFIGDIR" \
    -D "SQLDB_AS=$SQLDB_AS" \
    -D "SQLDB_MEM=$SQLDB_MEM" \
    -D "SQLDB_META=$SQLDB_META" \
    -f "$SANDBOX_PROFILE" \
    "$PI_BIN" \
      --provider "$PROVIDER" \
      --model "$MODEL" \
      --thinking "$THINKING" \
      "$@"
else
  exec "$PI_BIN" \
    --provider "$PROVIDER" \
    --model "$MODEL" \
    --thinking "$THINKING" \
    "$@"
fi
