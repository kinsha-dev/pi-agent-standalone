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
# Every path below is parametrized — override any of them from the environment
# before invoking (sensible defaults derive from the script location and $HOME):
#   PI_DIR              project root to sandbox      (default: this script's dir)
#   PI_HOME_DIR         pi runtime dir               (default: $HOME/.pi)
#   PI_GITCONFIG        git config file               (default: $HOME/.gitconfig)
#   PI_GITCONFIG_DIR    git config dir                (default: $HOME/.config/git)
#   PI_BIN              pi binary                     (default: $PI_DIR/node_modules/.bin/pi)
#   PI_SANDBOX_PROFILE  seatbelt profile             (default: $PI_DIR/pi-sandbox.sb)
#   PI_ENV_FILE         .env to read keys from        (default: $PI_DIR/.env)
#   PI_PROVIDER         LLM provider                  (default: openrouter)
#   PI_MODEL            LLM model                     (default: deepseek/deepseek-chat-v3.1)
set -euo pipefail

# Project root — default to the script's own directory, override with PI_DIR.
DIR="${PI_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Dynamic paths — all overridable from bash, all derived from DIR/$HOME by default.
PI_HOME_DIR="${PI_HOME_DIR:-$HOME/.pi}"
GITCONFIG="${PI_GITCONFIG:-$HOME/.gitconfig}"
GITCONFIGDIR="${PI_GITCONFIG_DIR:-$HOME/.config/git}"

# Trading SQL DBs (read+write by db_cli.js). They live in the data dir — the project's
# parent by default — i.e. OUTSIDE the sandboxed project, so the profile grants access
# to these exact files. Override the dir with PI_SQL_DATA_DIR or each path directly.
SQL_DATA_DIR="${PI_SQL_DATA_DIR:-$(cd "$DIR/.." && pwd)}"
SQLDB_AS="${PI_SQL_APP_STORE_DB:-$SQL_DATA_DIR/app_store.db}"
SQLDB_MEM="${PI_SQL_MEMORY_DB:-$SQL_DATA_DIR/memory.db}"
SQLDB_META="${PI_SQL_META_DB:-$SQL_DATA_DIR/meta.db}"
export PI_SQL_DATA_DIR SQLDB_AS SQLDB_MEM SQLDB_META
PI_BIN="${PI_BIN:-$DIR/node_modules/.bin/pi}"
SANDBOX_PROFILE="${PI_SANDBOX_PROFILE:-$DIR/pi-sandbox.sb}"
ENV_FILE="${PI_ENV_FILE:-$DIR/.env}"

# Pull only the keys pi needs from .env (the file has comments/parens that break `source`)
envval() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'"'"']//;s/["'"'"']$//'; }
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(envval OPENROUTER_API_KEY)}"
export GEMINI_API_KEY="${GEMINI_API_KEY:-$(envval GEMINI_API_KEY)}"

# Backend: OpenRouter DeepSeek V3.1 (override with PI_MODEL / PI_PROVIDER)
PROVIDER="${PI_PROVIDER:-openrouter}"
MODEL="${PI_MODEL:-deepseek/deepseek-chat-v3.1}"   # v3.1 tool-calls reliably; v3-0324 narrated instead of executing

# Fail fast on a misconfigured path rather than a cryptic sandbox error.
[ -f "$PI_BIN" ]          || { echo "❌ pi binary not found: $PI_BIN (set PI_BIN)" >&2; exit 1; }
[ -f "$SANDBOX_PROFILE" ] || { echo "❌ sandbox profile not found: $SANDBOX_PROFILE (set PI_SANDBOX_PROFILE)" >&2; exit 1; }

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "⚠️  OPENROUTER_API_KEY not set ($ENV_FILE) — pi can't reach the Claude model." >&2
fi

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
    "$@"
