#!/usr/bin/env bash
# safe-push.sh — guarded commit + push for the pi agent (and humans).
#
# The ONLY git-write path pi is allowed to use. Safety rails:
#   • Refuses to stage/commit secrets (.env, keys, creds) or *.bak backups.
#   • Scans the staged DIFF for live API keys / private keys and aborts if found.
#   • Never force-pushes, never rewrites history, never touches other branches.
#   • Pushes ONLY the current branch to origin.
#   • --dry-run shows what WOULD be committed without writing anything.
#
# Usage:
#   ./safe-push.sh "commit message"            # stage-guard-commit-push current branch
#   ./safe-push.sh --dry-run                    # preview staged files + guards, no commit
#
# Auth:
#   • Run from a normal shell  → uses your git credential helper (keychain).
#   • Run sandboxed by pi      → set GITHUB_TOKEN in .env (fine-grained PAT,
#     contents:write on THIS repo only). The token is fed via GIT_ASKPASS so it
#     never lands in argv, logs, or git config.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DRY=0; MSG=""
[ "${1:-}" = "--dry-run" ] && DRY=1 || MSG="${1:-}"

# Resolve the current branch. Distinguish three cases so we never misreport:
#   git errors (e.g. sandbox can't read ~/.gitconfig)  → show the real error
#   truly detached (symbolic-ref empty but git is fine) → detached message
#   on a branch                                          → proceed
if BR="$(git symbolic-ref --short -q HEAD 2>/tmp/sp_giterr)"; then
  :
else
  ERR="$(cat /tmp/sp_giterr 2>/dev/null); rm -f /tmp/sp_giterr"
  if echo "$ERR" | grep -qiE 'operation not permitted|unable to access|dubious ownership'; then
    echo "❌ git can't read its config in this environment:"; echo "   $ERR"
    echo "   (sandbox? ensure ~/.gitconfig is readable, or set repo-local identity with:"
    echo "    git config user.name <name> && git config user.email <email>)"
    exit 1
  fi
  echo "❌ detached HEAD — checkout a branch first:  git switch master"; exit 1
fi
rm -f /tmp/sp_giterr

# 1. Stage everything tracked-by-policy. .gitignore already excludes .env,
#    node_modules, *.json runtime data, *.bak backups, ~/.pi, etc.
git add -A

# 2. Filename guard — never commit obvious secrets/backups even if mis-ignored.
BAD="$(git diff --cached --name-only | grep -iE '(^|/)\.env($|\.)|\.bak|id_rsa|\.pem$|\.p12$|(^|/)credentials|\.key$|/auth\.json$' || true)"
if [ -n "$BAD" ]; then
  echo "❌ refusing — sensitive file(s) staged:"; echo "$BAD"; git reset -q; exit 1
fi

# 3. Content guard — scan the staged diff for live secrets.
if git diff --cached | grep -iqE 'sk-or-v1-[a-z0-9]{30}|nfp_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30}|-----BEGIN [A-Z ]*PRIVATE KEY'; then
  echo "❌ refusing — the staged diff contains what looks like an API key or private key."; git reset -q; exit 1
fi

# 4. Report staged set.
FILES="$(git diff --cached --name-only)"
if [ -z "$FILES" ]; then echo "nothing to commit — working tree clean"; exit 0; fi
echo "── staged for commit on '$BR' ──"; echo "$FILES" | sed 's/^/  /'

if [ "$DRY" = "1" ]; then echo "── dry run: no commit, no push ──"; git reset -q; exit 0; fi
[ -z "$MSG" ] && { echo "usage: ./safe-push.sh \"commit message\"  (or --dry-run)"; git reset -q; exit 1; }

# 5. Commit (no history rewrite).
git commit -q -m "$MSG

Committed via safe-push (pi agent guardrail)."
echo "✅ committed: $(git rev-parse --short HEAD)"

# 6. Push current branch only — never --force, never other refs.
TOKEN="$(grep -E '^GITHUB_TOKEN=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' ' || true)"
push_failed() {
  echo ""
  echo "⚠️  Commit is SAFE locally ($(git rev-parse --short HEAD)) — only the PUSH failed."
  echo "   Cause: no GITHUB_TOKEN in .env and the macOS keychain isn't reachable"
  echo "   (expected when pi runs sandboxed — the keychain lives outside the sandbox)."
  echo "   Fix it one of two ways:"
  echo "     1) Add a fine-grained PAT (contents:write on THIS repo only) to .env:"
  echo "          GITHUB_TOKEN=github_pat_xxx"
  echo "        then re-run ./safe-push.sh — it will push automatically."
  echo "     2) Or push from a normal terminal:  git push origin $BR"
  exit 1
}
if [ -n "$TOKEN" ]; then
  ASKPASS="$(mktemp "${TMPDIR:-/tmp}/sp_askpass.XXXX")"
  printf '#!/bin/sh\necho "%s"\n' "$TOKEN" > "$ASKPASS"; chmod 700 "$ASKPASS"
  trap 'rm -f "$ASKPASS"' EXIT
  GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
    git -c credential.username=x-access-token push origin "$BR" || push_failed
else
  GIT_TERMINAL_PROMPT=0 git push origin "$BR" || push_failed   # ambient keychain helper
fi
echo "✅ pushed '$BR' → origin"
