#!/usr/bin/env bash
# home_cache_cleanup.sh — reclaim disk from Docker, Claude Desktop VM bundles, and Ollama.
#
# DRY RUN by default. Each category is OPT-IN. Nothing is deleted without BOTH the
# category flag AND --apply. Deliberately EXCLUDES: whisper, LM Studio/Gemma, .colima,
# Android emulators (left untouched).
#
#   ./scripts/home_cache_cleanup.sh --docker --claude-vm --ollama          # preview all three
#   ./scripts/home_cache_cleanup.sh --docker --apply                       # prune docker for real
#   ./scripts/home_cache_cleanup.sh --claude-vm --apply                    # remove WARM cache only (safe)
#   ./scripts/home_cache_cleanup.sh --claude-vm-full --apply               # + active bundle (quit Claude first!)
#   OLLAMA_RM="llama3:8b qwen:7b" ./scripts/home_cache_cleanup.sh --ollama --apply   # remove named models
#   ./scripts/home_cache_cleanup.sh --ollama --ollama-all --apply          # remove ALL ollama models
set -uo pipefail

APPLY=0; DO_DOCKER=0; DO_CLAUDE=0; DO_CLAUDE_FULL=0; DO_OLLAMA=0; OLLAMA_ALL=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --docker) DO_DOCKER=1 ;;
    --claude-vm) DO_CLAUDE=1 ;;
    --claude-vm-full) DO_CLAUDE=1; DO_CLAUDE_FULL=1 ;;
    --ollama) DO_OLLAMA=1 ;;
    --ollama-all) OLLAMA_ALL=1 ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done
[ $((DO_DOCKER+DO_CLAUDE+DO_OLLAMA)) -eq 0 ] && {
  echo "Pick at least one: --docker  --claude-vm[-full]  --ollama   (add --apply to delete)"; exit 1; }

banner() { echo; echo "── $1 ──"; }
act()    { [ "$APPLY" = 1 ] && echo "  [APPLY] $*" || echo "  [dry-run] would: $*"; }

# ── 1. Docker ────────────────────────────────────────────────────────────────
if [ "$DO_DOCKER" = 1 ]; then
  banner "Docker"
  if ! command -v docker >/dev/null 2>&1; then
    echo "  docker CLI not found — skipping"
  elif ! docker info >/dev/null 2>&1; then
    echo "  Docker daemon not running — start Docker Desktop first, then re-run"
  else
    echo "  current usage:"; docker system df 2>/dev/null | sed 's/^/    /'
    # Removes: stopped containers, unused networks, dangling+unused images, build cache.
    # Does NOT touch volumes (your data) — that needs an explicit --volumes you can add.
    act "docker system prune -af   (unused images + build cache; volumes kept)"
    if [ "$APPLY" = 1 ]; then
      docker system prune -af
      echo "  note: Docker.raw may not shrink automatically — Docker Desktop →"
      echo "        Settings → Resources → 'Clean / Purge data' compacts the disk image."
    fi
  fi
fi

# ── 2. Claude Desktop VM bundles ──────────────────────────────────────────────
if [ "$DO_CLAUDE" = 1 ]; then
  banner "Claude Desktop VM bundles"
  VMROOT="$HOME/Library/Application Support/Claude/vm_bundles"
  if [ ! -d "$VMROOT" ]; then
    echo "  no vm_bundles dir — skipping"
  else
    # WARM prefetch cache — always safe to remove; the app re-fetches on demand.
    WARM="$VMROOT/warm"
    if [ -d "$WARM" ]; then
      sz=$(du -sh "$WARM" 2>/dev/null | cut -f1)
      act "rm -rf  '$WARM'   (prefetch cache, $sz — safe)"
      [ "$APPLY" = 1 ] && rm -rf "$WARM"
    else
      echo "  no warm/ cache present"
    fi
    # ACTIVE bundle — big reclaim, but the app must re-provision. Quit Claude first.
    if [ "$DO_CLAUDE_FULL" = 1 ]; then
      ACTIVE="$VMROOT/claudevm.bundle"
      if [ -d "$ACTIVE" ]; then
        sz=$(du -sh "$ACTIVE" 2>/dev/null | cut -f1)
        if pgrep -if "Claude" >/dev/null 2>&1; then
          echo "  ⚠️  Claude appears to be RUNNING. Quit Claude Desktop before --apply, or you"
          echo "      risk corrupting the live VM. Skipping active bundle this run."
        else
          act "rm -rf  '$ACTIVE'   (active VM, $sz — app re-provisions on next launch)"
          [ "$APPLY" = 1 ] && rm -rf "$ACTIVE"
        fi
      fi
    else
      echo "  (active bundle left intact — pass --claude-vm-full to also remove it, ~19 GB)"
    fi
  fi
fi

# ── 3. Ollama models ─────────────────────────────────────────────────────────
if [ "$DO_OLLAMA" = 1 ]; then
  banner "Ollama models"
  if ! command -v ollama >/dev/null 2>&1; then
    echo "  ollama CLI not found — skipping"
  else
    echo "  installed models:"; ollama list 2>/dev/null | sed 's/^/    /'
    targets=""
    if [ "$OLLAMA_ALL" = 1 ]; then
      targets=$(ollama list 2>/dev/null | awk 'NR>1{print $1}')
      echo "  --ollama-all: targeting ALL models above"
    elif [ -n "${OLLAMA_RM:-}" ]; then
      targets="$OLLAMA_RM"
      echo "  OLLAMA_RM: targeting: $OLLAMA_RM"
    else
      echo "  (no targets — set OLLAMA_RM=\"name1 name2\" or pass --ollama-all to remove)"
    fi
    for m in $targets; do
      act "ollama rm $m"
      [ "$APPLY" = 1 ] && ollama rm "$m"
    done
  fi
fi

echo
[ "$APPLY" = 1 ] && echo "✅ done." || echo "DRY RUN — add --apply to actually delete."
