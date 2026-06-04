#!/usr/bin/env bash
#
# Live site-API index generator for the drupal-agentic-workflow.
#
# Runs site-api.php through Drush against the bootstrapped site and writes the
# result to .claude/site-api.json — the ground-truth index (valid service IDs,
# real entity/bundle/field machine names, routes, permissions, modules) the
# agent consults BEFORE generating code, so it stops inventing identifiers.
#
# Usage (from the project root):
#   .claude/tools/site-api.sh            # writes .claude/site-api.json
#   .claude/tools/site-api.sh --print    # also prints the JSON to stdout
#
# Resolves the Drush runner the same way the lint hook resolves phpcs:
#   ddev (when .ddev/config.yaml exists) → vendor/bin/drush → global drush.
#
# Exit codes: 0 = wrote a valid index; 1 = could not run / site not bootable.
# A failure here is non-fatal for the workflow: .claude/project-map.md remains
# the static fallback.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCRIPT_REL=".claude/tools/site-api.php"
OUT_REL=".claude/site-api.json"
OUT_ABS="$PROJECT_DIR/$OUT_REL"
PRINT=false
[[ "${1:-}" == "--print" ]] && PRINT=true

# --- Resolve the Drush runner ------------------------------------------------
DRUSH_RUNNER=""
if command -v ddev &>/dev/null && [[ -f "$PROJECT_DIR/.ddev/config.yaml" ]]; then
  DRUSH_RUNNER="ddev drush"
elif [[ -x "$PROJECT_DIR/vendor/bin/drush" ]]; then
  DRUSH_RUNNER="$PROJECT_DIR/vendor/bin/drush"
elif command -v drush &>/dev/null; then
  DRUSH_RUNNER="drush"
else
  echo "site-api: no Drush runner found (ddev / vendor/bin/drush / global) — skipping." >&2
  echo "site-api: .claude/project-map.md remains the static fallback." >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/$SCRIPT_REL" ]]; then
  echo "site-api: extractor not found at $SCRIPT_REL — skipping." >&2
  exit 1
fi

# --- Run the extractor -------------------------------------------------------
# php:script resolves the path relative to the Drupal root, so pass an absolute
# path to be runner-agnostic (ddev bind-mounts the project, so it resolves too).
JSON=""
RUN_EXIT=0
# shellcheck disable=SC2086  # DRUSH_RUNNER ("ddev drush") must word-split.
JSON=$( cd "$PROJECT_DIR" && $DRUSH_RUNNER php:script "$SCRIPT_REL" 2>/dev/null ) || RUN_EXIT=$?

if [[ "$RUN_EXIT" -ne 0 || -z "$JSON" ]]; then
  echo "site-api: Drush could not bootstrap the site (is it installed / running?)." >&2
  echo "site-api: falling back to .claude/project-map.md." >&2
  exit 1
fi

# --- Validate it is JSON before overwriting ----------------------------------
if command -v jq &>/dev/null; then
  if ! printf '%s' "$JSON" | jq empty &>/dev/null; then
    echo "site-api: extractor output was not valid JSON — leaving existing index untouched." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$OUT_ABS")"
printf '%s\n' "$JSON" > "$OUT_ABS"

# --- Report ------------------------------------------------------------------
if command -v jq &>/dev/null; then
  COUNTS=$(printf '%s' "$JSON" | jq -r '
    "\(.services | length) services, " +
    "\(.entity_types | length) entity types, " +
    "\(.bundles | length) bundles, " +
    "\(.routes | length) routes, " +
    "\(.permissions | length) permissions, " +
    "\(.modules | length) modules"')
  echo "Wrote $OUT_REL ($COUNTS)"
else
  echo "Wrote $OUT_REL"
fi

[[ "$PRINT" == true ]] && printf '%s\n' "$JSON"
exit 0
