#!/usr/bin/env bash
#
# PreToolUse hook for Claude Code — Bash command guard.
# Blocks destructive operations that are hard to reverse.
# Exit code 2 = block the command (fed back to Claude as feedback).
#
set -euo pipefail

# ── Read hook input from stdin ───────────────────────────────────────────────
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ── Helper: block with reason ────────────────────────────────────────────────
block() {
  echo "BLOCKED: $1" >&2
  echo "This command is blocked by the pre-bash-guard hook to prevent accidental data loss." >&2
  echo "If you need to run this command, ask the user to run it manually." >&2
  exit 2
}

# ── Destructive git operations ───────────────────────────────────────────────
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  block "git reset --hard — destroys uncommitted changes"
fi

if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s*\.|git\s+checkout\s+\.$'; then
  block "git checkout -- . — discards all working tree changes"
fi

if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  block "git clean -f — permanently deletes untracked files"
fi

if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+-f\b'; then
  block "git push --force — rewrites remote history"
fi

if echo "$COMMAND" | grep -qE 'git\s+branch\s+-D\b'; then
  block "git branch -D — force-deletes a branch without merge check"
fi

# ── Destructive filesystem operations ────────────────────────────────────────
if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*rf?\s+/\s|rm\s+-[a-zA-Z]*rf?\s+\.$|rm\s+-[a-zA-Z]*rf?\s+\.\.$'; then
  block "rm -rf on root/project directory — catastrophic file deletion"
fi

# ── Destructive DDEV operations ──────────────────────────────────────────────
if echo "$COMMAND" | grep -qE 'ddev\s+delete\b'; then
  block "ddev delete — destroys the DDEV project and its database"
fi

# ── Destructive SQL operations ───────────────────────────────────────────────
if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE)\b'; then
  block "DROP TABLE/DATABASE — permanently destroys database objects"
fi

# ── All clear ────────────────────────────────────────────────────────────────
exit 0
