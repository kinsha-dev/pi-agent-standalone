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

DRY=0; MSG=""; DEPLOY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --deploy)  DEPLOY=1 ;;
    *)         MSG="$arg" ;;
  esac
done

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
[ -z "$MSG" ] && { echo "usage: ./safe-push.sh \"commit message\" [--deploy] [--dry-run]"; git reset -q; exit 1; }

# 5. Commit (no history rewrite).
DEPLOY_TAG=""
[ "$DEPLOY" = "1" ] && DEPLOY_TAG=" [deploy]"
git commit -q -m "$MSG$DEPLOY_TAG

Committed via safe-push (pi agent guardrail)."
echo "✅ committed: $(git rev-parse --short HEAD)"

# 6. Push current branch only — never --force, never other refs.
TOKEN="$(grep -E '^GITHUB_TOKEN=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' ' || true)"

# Capture the push output so push_failed can diagnose the ACTUAL cause instead of
# always blaming auth. Single EXIT trap cleans up both temp files.
PUSHLOG="$(mktemp "${TMPDIR:-/tmp}/sp_push.XXXX")"
ASKPASS=""
cleanup() { rm -f "$PUSHLOG" "$ASKPASS" 2>/dev/null || true; }
trap cleanup EXIT

push_failed() {
  echo "" >&2
  echo "⚠️  Commit is SAFE locally ($(git rev-parse --short HEAD)) — only the PUSH failed." >&2
  if grep -qiE 'fetch first|non-fast-forward|\[rejected\]|tip of your current branch is behind' "$PUSHLOG"; then
    echo "   Cause: remote '$BR' has commits you don't have locally (non-fast-forward)." >&2
    echo "   Fix: integrate the remote changes, then push again — e.g." >&2
    echo "        git pull --rebase origin $BR && ./safe-push.sh \"<message>\"" >&2
    echo "   (Your commit is preserved; --rebase replays it on top. Never --force.)" >&2
  elif grep -qiE 'authentication failed|could not read Username|terminal prompts disabled|403 Forbidden|permission to .* denied|invalid username or password|remote: Support for password' "$PUSHLOG"; then
    echo "   Cause: authentication failed — no usable credential for origin" >&2
    echo "   (expected when pi runs sandboxed — the keychain lives outside the sandbox)." >&2
    echo "   Fix it one of two ways:" >&2
    echo "     1) Add a fine-grained PAT (contents:write on THIS repo only) to .env:" >&2
    echo "          GITHUB_TOKEN=github_pat_xxx" >&2
    echo "        then re-run ./safe-push.sh — it will push automatically." >&2
    echo "     2) Or push from a normal terminal:  git push origin $BR" >&2
  else
    echo "   Cause: push failed for an unexpected reason — see git's output above." >&2
    echo "   Fix: resolve the issue shown, then re-run ./safe-push.sh (commit is preserved)." >&2
  fi
  exit 1
}

if [ -n "$TOKEN" ]; then
  # Hardened askpass: the script body is a FIXED literal that only echoes an env var.
  # The token is passed via the environment (SP_GH_TOKEN), never interpolated into the
  # script source — so a malicious/poisoned token value can't inject shell commands.
  ASKPASS="$(mktemp "${TMPDIR:-/tmp}/sp_askpass.XXXX")"
  printf '#!/bin/sh\nprintf %%s "$SP_GH_TOKEN"\n' > "$ASKPASS"; chmod 700 "$ASKPASS"
  SP_GH_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
    git -c credential.username=x-access-token push origin "$BR" 2>&1 | tee "$PUSHLOG" || push_failed
else
  GIT_TERMINAL_PROMPT=0 git push origin "$BR" 2>&1 | tee "$PUSHLOG" || push_failed   # ambient keychain helper
fi
echo "✅ pushed '$BR' → origin"
