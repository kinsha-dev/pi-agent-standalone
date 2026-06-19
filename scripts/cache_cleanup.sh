#!/usr/bin/env bash
# cache_cleanup.sh — reclaim space from regenerable cruft (graph backups, logs, .bak files).
#
#   ./scripts/cache_cleanup.sh            # DRY RUN — shows what would be removed
#   ./scripts/cache_cleanup.sh --apply    # actually delete
#   KEEP_BACKUPS=2 ./scripts/cache_cleanup.sh --apply   # keep N newest graph backups (default 1)
#
# SAFE BY DESIGN: only removes regenerable artifacts. NEVER touches .env, source files,
# databases (*.db), or the current graph outputs (graph.json/graph.html/GRAPH_REPORT.md/
# app_agent.md). Everything it removes is rebuilt by graphify or recreated on next run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
KEEP_BACKUPS="${KEEP_BACKUPS:-1}"

freed=0
note() { printf '%s\n' "$*"; }
human() { du -sh "$1" 2>/dev/null | cut -f1; }

# Add a target: if it exists, account for its size and (when --apply) remove it.
rm_target() {
    local path="$1" label="$2"
    [ -e "$path" ] || return 0
    local sz; sz=$(du -sk "$path" 2>/dev/null | cut -f1 || echo 0)
    freed=$((freed + sz))
    if [ "$APPLY" = "1" ]; then
        rm -rf "$path"
        note "  removed  $label  ($(( sz )) KB)  $path"
    else
        note "  would remove  $label  ($(( sz )) KB)  $path"
    fi
}

note "── cache cleanup ${APPLY:+}$([ "$APPLY" = 1 ] && echo '(APPLY)' || echo '(dry run — pass --apply to delete)') ──"
note "root: $ROOT"
note ""

# 1. Dated graphify graph backups (graphify writes one per rebuild). Keep the newest N.
note "graphify graph backups (keeping newest $KEEP_BACKUPS):"
for base in "$ROOT/graphify-out" "$ROOT/pi-agent-standalone/graphify-out"; do
    [ -d "$base" ] || continue
    # dated dirs look like 2026-06-15; sort newest-last, drop the tail to keep (bash 3.2 safe)
    dated=$(find "$base" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]' 2>/dev/null | sort)
    local_total=$(printf '%s\n' "$dated" | grep -c . || true)
    keep_from=$(( local_total - KEEP_BACKUPS ))
    [ "$keep_from" -lt 0 ] && keep_from=0
    idx=0
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        if [ "$idx" -lt "$keep_from" ]; then rm_target "$d" "graph-backup"; fi
        idx=$((idx + 1))
    done < <(printf '%s\n' "$dated")
done
note ""

# 2. graphify temp/scratch files (regenerated each run).
note "graphify scratch files:"
for base in "$ROOT/graphify-out" "$ROOT/pi-agent-standalone/graphify-out"; do
    [ -d "$base" ] || continue
    rm_target "$base/.graphify_old.json" "graphify-old"
    for f in "$base"/.graphify_chunk_*.json "$base"/.graphify_extract.json "$base"/.graphify_ast.json \
             "$base"/.graphify_semantic.json "$base"/.graphify_detect.json "$base"/.graphify_analysis.json \
             "$base"/.graphify_incremental.json; do
        [ -e "$f" ] && rm_target "$f" "graphify-tmp"
    done
done
note ""

# 3. Rebuild log (truncate, don't delete — the hook appends to it).
LOG="${HOME}/.cache/graphify-rebuild.log"
if [ -f "$LOG" ]; then
    sz=$(du -sk "$LOG" 2>/dev/null | cut -f1 || echo 0)
    freed=$((freed + sz))
    if [ "$APPLY" = "1" ]; then : > "$LOG"; note "  truncated  rebuild-log  ($sz KB)  $LOG"
    else note "  would truncate  rebuild-log  ($sz KB)  $LOG"; fi
fi
note ""

# 4. Stray backup files from edits/migrations (NEVER the live .env or *.db).
note "backup files (.bak):"
while IFS= read -r f; do rm_target "$f" "bak-file"; done < <(
    find "$ROOT" -maxdepth 2 \
        \( -name '.env.bak.*' -o -name '*.db.bak-*' -o -name '*.json.bak-*' \
           -o -name '*.json.bak2-*' -o -name '_*.bak' -o -name '*.bak.[0-9]*' \) \
        -not -path '*/node_modules/*' 2>/dev/null
)
note ""

mb=$(awk "BEGIN{printf \"%.1f\", $freed/1024}")
if [ "$APPLY" = "1" ]; then
    note "✅ freed ~${mb} MB"
else
    note "DRY RUN — would free ~${mb} MB. Re-run with --apply to delete."
fi
