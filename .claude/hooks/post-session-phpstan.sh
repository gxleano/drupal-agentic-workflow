#!/usr/bin/env bash
#
# Stop hook: run PHPStan on changed PHP files when Claude finishes a turn.
# Errors (or a PHPStan that cannot run at all) are sent back to Claude once
# with exit 2. On the follow-up stop (stop_hook_active) the hook only reports,
# so a file with pre-existing errors cannot trap Claude in a loop.
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

# ── Hook input ───────────────────────────────────────────────────────────────
INPUT="{}"
[[ -t 0 ]] || INPUT=$(cat)
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)

# Claude Code ignores any exit code but 0 and 2, so a crash would pass in
# silence and the changes would look analysed. Say so with exit 2 — except on
# the follow-up stop, where it only reports, as for code errors.
hook_broken() {
  echo "post-session-phpstan.sh could not analyse the changes: $1" >&2
  [[ "$STOP_ACTIVE" == "true" ]] && exit 0
  exit 2
}
on_exit() {
  local rc=$?
  cleanup
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    hook_broken "unexpected failure (exit $rc)."
  fi
}
# Cleans the synthesized config (see below) as well. An EXIT trap, not ERR:
# it is not inherited by $(…), where phpstan exits 1 on purpose.
TMP_CONFIG=""
cleanup() {
  if [[ -n "$TMP_CONFIG" && -f "$TMP_CONFIG" ]]; then
    rm -f "$TMP_CONFIG"
  fi
}
trap on_exit EXIT

# ── Resolve project root ─────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Shared PHP tool resolution (DDEV → vendor/bin → $PATH → global Composer).
HOOK_LIB="$(dirname "$0")/lib/php-tools.sh"
[[ -f "$HOOK_LIB" ]] || hook_broken "$HOOK_LIB is missing. Reinstall the hooks (vendor/bin/daw update) or ask the user to."
# shellcheck source=lib/php-tools.sh
source "$HOOK_LIB"

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
# New files count too: `git diff` leaves out untracked files, which is what a
# freshly generated module is. The project's own diff only shows that a
# submodule moved, not which of its files changed, so each submodule is read
# too, with its path in front.
submodule_changes() {
  [[ -f "$PROJECT_DIR/.gitmodules" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" && -d "$PROJECT_DIR/$path" ]] || continue
    { git -C "$PROJECT_DIR/$path" diff --name-only HEAD 2>/dev/null
      git -C "$PROJECT_DIR/$path" ls-files --others --exclude-standard 2>/dev/null; } | sed "s|^|$path/|" || true
  done < <(git config -f "$PROJECT_DIR/.gitmodules" --get-regexp '\.path$' 2>/dev/null | awk '{print $2}')
}
CHANGED_FILES=$(
  { git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_DIR" diff --name-only 2>/dev/null
    git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null
    submodule_changes; } \
  | sort -u \
  | grep -E '\.(php|module|theme|install|inc|profile|test)$' \
  | grep -v -E '^(vendor/|web/core/|web/modules/contrib/|web/themes/contrib/|web/profiles/)' \
  || true
)

if [[ "$CONTEXT" == "site" ]]; then
  CHANGED_FILES=$(echo "$CHANGED_FILES" | grep -E '^web/modules/custom/' || true)
fi

# Only what Claude wrote or edited in this session (the lint hook keeps the
# list): uncommitted work of someone else would come back on every turn.
# Without a session id (an older Claude Code, a manual run) every changed file
# counts. Edits made through shell commands are not on the list.
EDITS_FILE=$(session_edits_file "$INPUT")
if [[ -n "$EDITS_FILE" ]]; then
  if [[ ! -f "$EDITS_FILE" ]]; then
    exit 0
  fi
  CHANGED_FILES=$(grep -Fxf <(sort -u "$EDITS_FILE") <<< "$CHANGED_FILES" || true)
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
  echo "──────────────────────────────────────────────"
  exit 0
fi

# A config or bootstrap failure is not a code problem: say so plainly instead
# of letting it look like a clean run.
if grep -qiE 'Invalid configuration|Unexpected item|could not be (found|loaded)|Bootstrap file|not a valid' <<< "$PHPSTAN_OUTPUT"; then
  SUMMARY="PHPStan could not run — its configuration is broken (not a code error)."
  ADVICE="Tell the user what is broken. Do not change phpstan.neon without asking."
else
  SUMMARY="PHPStan found errors in the changed files."
  ADVICE="Fix the errors in code you changed this session. List pre-existing errors for the user instead of fixing them."
fi

if [[ "$STOP_ACTIVE" == "true" ]]; then
  # Already sent back once this stop cycle: report only.
  echo "  Result  : $SUMMARY"
  echo ""
  echo "$PHPSTAN_OUTPUT"
  echo "──────────────────────────────────────────────"
  exit 0
fi

{
  echo "$SUMMARY"
  echo "$ADVICE"
  echo ""
  echo "$PHPSTAN_OUTPUT"
} >&2
exit 2
