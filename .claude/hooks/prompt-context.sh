#!/usr/bin/env bash
#
# UserPromptSubmit hook for Claude Code — Git context injection.
# Injects a 1-2 line git status summary at prompt submit.
#
# This hook is OPT-IN. To enable, add the following to your
# .claude/settings.local.json (NOT settings.json):
#
# {
#   "hooks": {
#     "UserPromptSubmit": [
#       {
#         "matcher": "",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prompt-context.sh",
#             "timeout": 5
#           }
#         ]
#       }
#     ]
#   }
# }
#
set -euo pipefail

# ── Check if we're in a git repo ─────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# ── Gather git status summary ────────────────────────────────────────────────
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")

# Count file statuses (fast, no -uall)
MODIFIED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

# Build summary parts
PARTS=()
if [[ "$STAGED" -gt 0 ]]; then
  PARTS+=("${STAGED} staged")
fi
if [[ "$MODIFIED" -gt 0 ]]; then
  PARTS+=("${MODIFIED} modified")
fi
if [[ "$UNTRACKED" -gt 0 ]]; then
  PARTS+=("${UNTRACKED} untracked")
fi

# Only output if there's something to report
if [[ ${#PARTS[@]} -gt 0 ]]; then
  SUMMARY=$(IFS=', '; echo "${PARTS[*]}")
  echo "[Git: ${BRANCH} — ${SUMMARY}]"
else
  echo "[Git: ${BRANCH} — clean]"
fi

exit 0
