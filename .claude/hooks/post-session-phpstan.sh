#!/usr/bin/env bash
#
# Stop hook: run PHPStan on PHP files changed in this session.
# Fires once when Claude finishes a turn — output is shown to the user,
# not fed back to Claude. Never exits 2 (informational only).
#
set -euo pipefail

# ── Resolve project root ─────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# ── Require DDEV ─────────────────────────────────────────────────────────────
if ! command -v ddev &>/dev/null; then
  exit 0
fi

if ! ddev status 2>/dev/null | grep -q "running"; then
  exit 0
fi

# ── Require phpstan.neon ──────────────────────────────────────────────────────
if [[ ! -f "$PROJECT_DIR/phpstan.neon" ]]; then
  exit 0
fi

# ── Collect changed PHP files (staged + unstaged, custom code only) ──────────
CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null; \
                git -C "$PROJECT_DIR" diff --name-only 2>/dev/null) \
  | sort -u \
  | grep -E '\.(php|module|theme|install|inc|profile|test)$' \
  | grep -v -E '^(vendor/|web/core/|web/modules/contrib/|web/themes/contrib/|web/profiles/)' \
  | grep -E '^web/modules/custom/' \
  || true

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')

echo ""
echo "──────────────────────────────────────────────"
echo "  PHPStan — post-session analysis"
echo "  Files   : $FILE_COUNT changed PHP file(s)"
echo "──────────────────────────────────────────────"

# ── Run PHPStan inside DDEV ───────────────────────────────────────────────────
PHPSTAN_EXIT=0
PHPSTAN_OUTPUT=$(ddev exec phpstan analyse \
  --no-progress \
  --memory-limit=512M \
  --error-format=table \
  $CHANGED_FILES 2>&1) || PHPSTAN_EXIT=$?

if [[ "$PHPSTAN_EXIT" -eq 0 ]]; then
  echo "  Result  : PASSED — no errors found"
else
  echo "  Result  : issues found (exit $PHPSTAN_EXIT)"
  echo ""
  echo "$PHPSTAN_OUTPUT"
  echo ""
  echo "  Tip: ask Claude to fix PHPStan errors, or run manually:"
  echo "    ddev exec phpstan analyse --no-progress web/modules/custom"
fi

echo "──────────────────────────────────────────────"
echo ""

exit 0
