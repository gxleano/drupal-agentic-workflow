#!/usr/bin/env bash
#
# Stop hook: run PHPStan on PHP files changed in this session.
# Fires once when Claude finishes a turn — output is shown to the user,
# not fed back to Claude. Never exits 2 (informational only).
#
# Works in two contexts (see lib/php-tools.sh):
#   • Drupal site    — runs phpstan via DDEV (or a local binary) on changed
#                      files under web/modules/custom/.
#   • Standalone repo — a contrib module/theme/profile with no Drupal install:
#                      runs a local phpstan on changed PHP files anywhere in the
#                      repo, synthesizing a phpstan-drupal config when the repo
#                      ships none.
#
set -euo pipefail

# ── Resolve project root ─────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Shared PHP tool resolution (DDEV → vendor/bin → $PATH → global Composer).
source "$(dirname "$0")/lib/php-tools.sh"

# ── Resolve a phpstan runner ─────────────────────────────────────────────────
# No DDEV requirement any more: fall back to a local binary so a contrib repo
# without a Drupal installation still gets analysed.
if ! php_resolve_tool "$PROJECT_DIR" phpstan; then
  # Nothing to run with — stay silent unless the repo clearly expects phpstan.
  if [[ -f "$PROJECT_DIR/phpstan.neon" || -f "$PROJECT_DIR/phpstan.neon.dist" ]]; then
    echo "" >&2
    echo "  PHPStan: a phpstan config exists but no phpstan binary was found" >&2
    echo "  (looked in DDEV, vendor/bin, \$PATH and the global Composer bin)." >&2
    echo "  Install it with: composer require --dev phpstan/phpstan mglaman/phpstan-drupal" >&2
  fi
  exit 0
fi
PHPSTAN_RUNNER="$PHP_TOOL_RUNNER"
PHPSTAN_BIN="$PHP_TOOL_BIN"
PHPSTAN_SOURCE="$PHP_TOOL_SOURCE"

CONTEXT=$(php_project_context "$PROJECT_DIR")

# ── Collect changed PHP files (staged + unstaged) ────────────────────────────
# Site context keeps the original web/modules/custom/ scope; a standalone repo
# scans changed PHP anywhere (still excluding vendored/contrib/core code).
CHANGED_FILES=$(
  { git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_DIR" diff --name-only 2>/dev/null; } \
  | sort -u \
  | grep -E '\.(php|module|theme|install|inc|profile|test)$' \
  | grep -v -E '^(vendor/|web/core/|web/modules/contrib/|web/themes/contrib/|web/profiles/)' \
  || true
)

if [[ "$CONTEXT" == "site" ]]; then
  CHANGED_FILES=$(echo "$CHANGED_FILES" | grep -E '^web/modules/custom/' || true)
fi

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')

# ── Resolve the phpstan configuration ────────────────────────────────────────
# Prefer the repo's own config so we agree with CI. When a standalone module
# ships none, synthesize a minimal phpstan-drupal config (level 1) so analysis
# still runs. Config synthesis only applies to local runs — host paths cannot
# be referenced from inside a DDEV container, so DDEV keeps the existing
# "requires a project phpstan.neon" behaviour.
CONFIG_ARGS=()
CONFIG_NOTE=""
TMP_CONFIG=""
cleanup() { [[ -n "$TMP_CONFIG" && -f "$TMP_CONFIG" ]] && rm -f "$TMP_CONFIG"; }
trap cleanup EXIT

# NOTE: php_exec_tool cd's to the project root on the host, and `ddev exec`
# runs in the container's project root too — so a *relative* config path
# resolves correctly in both. An absolute host path would break inside DDEV.
if [[ -f "$PROJECT_DIR/phpstan.neon" ]]; then
  CONFIG_ARGS=(--configuration=phpstan.neon)
  CONFIG_NOTE="phpstan.neon"
elif [[ -f "$PROJECT_DIR/phpstan.neon.dist" ]]; then
  CONFIG_ARGS=(--configuration=phpstan.neon.dist)
  CONFIG_NOTE="phpstan.neon.dist"
elif [[ "$PHPSTAN_SOURCE" == "ddev" ]]; then
  # No config and a containerised runner — nothing safe to synthesize.
  exit 0
else
  # Local run with no project config: synthesize one.
  EXTENSION_NEON=$(php_find_phpstan_drupal "$PROJECT_DIR" "$PHPSTAN_BIN" || true)
  TMP_CONFIG="${TMPDIR:-/tmp}/claude-phpstan-$$.neon"
  if [[ -n "$EXTENSION_NEON" ]]; then
    {
      echo "includes:"
      echo "    - $EXTENSION_NEON"
      RULES_NEON="${EXTENSION_NEON%/extension.neon}/rules.neon"
      [[ -f "$RULES_NEON" ]] && echo "    - $RULES_NEON"
      echo "parameters:"
      echo "    level: 1"
    } > "$TMP_CONFIG"
    CONFIG_NOTE="synthesized phpstan-drupal default (level 1)"
  else
    {
      echo "parameters:"
      echo "    level: 1"
    } > "$TMP_CONFIG"
    CONFIG_NOTE="synthesized barebones config (level 1, phpstan-drupal not installed)"
  fi
  CONFIG_ARGS=(--configuration="$TMP_CONFIG")
fi

echo ""
echo "──────────────────────────────────────────────"
echo "  PHPStan — post-session analysis"
echo "  Context : $CONTEXT (runner: $PHPSTAN_SOURCE)"
echo "  Config  : $CONFIG_NOTE"
echo "  Files   : $FILE_COUNT changed PHP file(s)"
echo "──────────────────────────────────────────────"

# ── Run PHPStan ──────────────────────────────────────────────────────────────
PHPSTAN_EXIT=0
# shellcheck disable=SC2086  # $CHANGED_FILES is an intentional word list.
PHPSTAN_OUTPUT=$(php_exec_tool "$PROJECT_DIR" "$PHPSTAN_RUNNER" "$PHPSTAN_BIN" \
  analyse \
  --no-progress \
  --memory-limit=512M \
  --error-format=table \
  "${CONFIG_ARGS[@]}" \
  $CHANGED_FILES 2>&1) || PHPSTAN_EXIT=$?

if [[ "$PHPSTAN_EXIT" -eq 0 ]]; then
  echo "  Result  : PASSED — no errors found"
else
  echo "  Result  : issues found (exit $PHPSTAN_EXIT)"
  echo ""
  echo "$PHPSTAN_OUTPUT"
  echo ""
  echo "  Tip: ask Claude to fix PHPStan errors, or run manually:"
  if [[ "$PHPSTAN_SOURCE" == "ddev" ]]; then
    echo "    ddev exec phpstan analyse --no-progress web/modules/custom"
  else
    echo "    phpstan analyse --no-progress <path>"
  fi
fi

echo "──────────────────────────────────────────────"
echo ""

exit 0
