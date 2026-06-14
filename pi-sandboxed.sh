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
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pull only the keys pi needs from .env (the file has comments/parens that break `source`)
envval() { grep -E "^$1=" "$DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'"'"']//;s/["'"'"']$//'; }
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(envval OPENROUTER_API_KEY)}"
export GEMINI_API_KEY="${GEMINI_API_KEY:-$(envval GEMINI_API_KEY)}"

# Backend: OpenRouter DeepSeek V3 only (override with PI_MODEL / PI_PROVIDER)
PROVIDER="${PI_PROVIDER:-openrouter}"
MODEL="${PI_MODEL:-deepseek/deepseek-chat-v3.1}"   # v3.1 tool-calls reliably; v3-0324 narrated instead of executing

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "⚠️  OPENROUTER_API_KEY not set in .env — pi can't reach the Claude model." >&2
fi

exec sandbox-exec -D "DIR=$DIR" -D "PIHOME=$HOME/.pi" -D "PM2HOME=${PM2_HOME:-$HOME/.pm2}" \
  -D "GITCONFIG=$HOME/.gitconfig" -D "GITCONFIGDIR=$HOME/.config/git" -f "$DIR/pi-sandbox.sb" \
  "$DIR/node_modules/.bin/pi" \
    --provider "$PROVIDER" \
    --model "$MODEL" \
    "$@"
