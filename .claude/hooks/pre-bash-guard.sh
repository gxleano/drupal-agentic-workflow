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

# rm -rf targeting the home directory (literal ~ or $HOME).
if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*rf?\s+(~|\$HOME)(/[^[:space:]]*)?(\s|$)'; then
  block "rm -rf on home directory — catastrophic file deletion"
fi

# ── Destructive DDEV operations ──────────────────────────────────────────────
if echo "$COMMAND" | grep -qE 'ddev\s+delete\b'; then
  block "ddev delete — destroys the DDEV project and its database"
fi

# ── Destructive Drush operations ─────────────────────────────────────────────
# Drush accepts both the `cmd:sub` and legacy `cmd-sub` separators, so match
# either. These wipe the database, content, or critical state with no undo.
if echo "$COMMAND" | grep -qE 'drush\s+([a-z-]+\s+)*sql[:-]drop\b'; then
  block "drush sql:drop — drops every table in the database"
fi

if echo "$COMMAND" | grep -qiE 'drush\s+.*sql[:-](query|cli).*\b(DROP|TRUNCATE|DELETE)\b'; then
  block "drush sql:query with DROP/TRUNCATE/DELETE — destroys data"
fi

if echo "$COMMAND" | grep -qE 'drush\s+([a-z-]+\s+)*entity[:-]delete\b'; then
  block "drush entity:delete — bulk-deletes content entities"
fi

if echo "$COMMAND" | grep -qE 'drush\s+([a-z-]+\s+)*field[:-]delete\b'; then
  block "drush field:delete — removes a field and all its data"
fi

if echo "$COMMAND" | grep -qE 'drush\s+([a-z-]+\s+)*state[:-]delete\b'; then
  block "drush state:delete — removes persisted system state"
fi

if echo "$COMMAND" | grep -qE 'drush\s+([a-z-]+\s+)*user[:-]cancel\b'; then
  block "drush user:cancel — cancels/deletes user accounts and their content"
fi

# ── Destructive SQL operations ───────────────────────────────────────────────
if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE)\b'; then
  block "DROP TABLE/DATABASE — permanently destroys database objects"
fi

# ── Local secrets reaching git ───────────────────────────────────────────────
# .env files and settings.local.php hold credentials. `.env.example`-style
# templates are fine, so only the real files match.
SECRET_RE='(^|/)(\.env|\.env\.local|\.env\.[^/]+\.local|settings\.local\.php)$'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Print the first secret path read from stdin, if any. (Blocking happens in
# the caller: `exit` inside a piped loop would only leave the subshell.)
first_secret() {
  grep -E "$SECRET_RE" | head -n 1 || true
}

block_if_secret() {
  [[ -n "$2" ]] && block "$1 would put $2 into git — it holds local secrets"
  return 0
}

if echo "$COMMAND" | grep -qE 'git\s+add\b'; then
  # Explicit paths, including `git add -f`, which bypasses .gitignore.
  block_if_secret "git add" "$(echo "$COMMAND" | tr -s ' \t;&|' '\n' | first_secret)"
  # `git add -A` / `--all` / `.` picks up untracked files that are not ignored.
  if echo "$COMMAND" | grep -qE 'git\s+add\s+(.*\s)?(-A|--all|\.)(\s|$)'; then
    block_if_secret "git add" "$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null | first_secret)"
  fi
fi

if echo "$COMMAND" | grep -qE 'git\s+commit\b'; then
  block_if_secret "git commit" "$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | first_secret)"
  # `commit -a` also commits modified tracked files.
  if echo "$COMMAND" | grep -qE 'git\s+commit\s+(.*\s)?(-[a-zA-Z]*a[a-zA-Z]*|--all)(\s|$)'; then
    block_if_secret "git commit -a" "$(git -C "$PROJECT_DIR" diff --name-only 2>/dev/null | first_secret)"
  fi
fi

# ── All clear ────────────────────────────────────────────────────────────────
exit 0
