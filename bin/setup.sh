#!/usr/bin/env bash
#
# setup.sh — Install drupal-agentic-workflow into a target Drupal project.
#
# Usage: bin/setup.sh [TARGET_DIR] [OPTIONS]
#   TARGET_DIR    Path to a Drupal project root (default: current directory)
#   --force       Skip Drupal project detection
#   --dry-run     Show what would be done without making changes
#   --help        Show this help message
#
# Phases:
#   0. Validate target is a Drupal project (composer.json with drupal/core)
#   1. Copy .claude/ directory (skills, hooks, settings)
#   2. Append Drupal rules to CLAUDE.md (or create from template)
#   3. Install .prettierrc.json (if missing)
#   4. Scan web/modules/custom/ and create AI_CONTEXT.md templates for modules missing one
#   5. Print summary with counts and next steps
#
# Idempotency rules:
#   - File exists and matches source → "up to date"
#   - File exists and differs → "SKIPPED (customized)" — never overwrite user changes
#   - File missing → copy and log "installed"

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve TEMPLATE_DIR: the root of the drupal-agentic-workflow repository.
# This script lives at bin/setup.sh, so the template root is one level up.
# ---------------------------------------------------------------------------
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Color helpers — degrade gracefully when output is not a terminal.
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  GRAY=$(tput setaf 8)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
else
  GREEN=""
  YELLOW=""
  GRAY=""
  BOLD=""
  RESET=""
fi

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
INSTALLED=0
UP_TO_DATE=0
SKIPPED=0

# ---------------------------------------------------------------------------
# Flags / defaults
# ---------------------------------------------------------------------------
TARGET_DIR=""
FORCE=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'HELP'
Usage: bin/setup.sh [TARGET_DIR] [OPTIONS]

Install drupal-agentic-workflow into a target Drupal project.

Arguments:
  TARGET_DIR    Path to a Drupal project root (default: current directory)

Options:
  --force       Skip Drupal project detection
  --dry-run     Show what would be done without making changes
  --help        Show this help message

Phases:
  0. Validate target is a Drupal project (composer.json with drupal/core)
  1. Copy .claude/ directory (skills, hooks, settings)
  2. Append Drupal rules to CLAUDE.md (or create from template)
  3. Install .prettierrc.json (if missing)
  4. Scan web/modules/custom/ and create AI_CONTEXT.md templates
  5. Print summary with counts and next steps
HELP
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
      else
        echo "Error: Unexpected argument '$1'" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# Default TARGET_DIR to the current working directory.
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(pwd)"
fi

# Normalise to an absolute path.
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Target directory does not exist: $TARGET_DIR" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Helper: log with prefix
# ---------------------------------------------------------------------------
log_installed() {
  echo "  ${GREEN}✚ installed:${RESET} $1"
}

log_up_to_date() {
  echo "  ${GRAY}✓ up to date:${RESET} $1"
}

log_skipped() {
  echo "  ${YELLOW}⊘ SKIPPED (customized):${RESET} $1"
}

# ---------------------------------------------------------------------------
# Helper: install_file SOURCE DEST
#
# Implements the idempotency rules described at the top of this file.
# ---------------------------------------------------------------------------
install_file() {
  local src="$1"
  local dest="$2"
  local relative_dest="${dest#"$TARGET_DIR"/}"

  if [[ -f "$dest" ]]; then
    # Compare contents
    if diff -q "$src" "$dest" &>/dev/null; then
      log_up_to_date "$relative_dest"
      UP_TO_DATE=$((UP_TO_DATE + 1))
    else
      log_skipped "$relative_dest"
      SKIPPED=$((SKIPPED + 1))
    fi
  else
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "$relative_dest (dry-run)"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      log_installed "$relative_dest"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Helper: install_file_executable SOURCE DEST
#
# Same as install_file but also sets the executable bit after copying.
# ---------------------------------------------------------------------------
install_file_executable() {
  local src="$1"
  local dest="$2"
  local relative_dest="${dest#"$TARGET_DIR"/}"

  if [[ -f "$dest" ]]; then
    if diff -q "$src" "$dest" &>/dev/null; then
      log_up_to_date "$relative_dest"
      UP_TO_DATE=$((UP_TO_DATE + 1))
    else
      log_skipped "$relative_dest"
      SKIPPED=$((SKIPPED + 1))
    fi
  else
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "$relative_dest (dry-run)"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      chmod +x "$dest"
      log_installed "$relative_dest"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Phase 0 — Validate target is a Drupal project
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 0: Validating Drupal project${RESET}"
echo "  Target: $TARGET_DIR"

if [[ "$FORCE" == true ]]; then
  echo "  ${YELLOW}--force: skipping Drupal project detection${RESET}"
elif [[ ! -f "$TARGET_DIR/composer.json" ]]; then
  echo "  ${YELLOW}Error: No composer.json found in $TARGET_DIR${RESET}" >&2
  echo "  This does not appear to be a Drupal project." >&2
  echo "  Use --force to skip this check." >&2
  exit 1
elif ! grep -q '"drupal/core' "$TARGET_DIR/composer.json"; then
  echo "  ${YELLOW}Error: composer.json does not reference drupal/core${RESET}" >&2
  echo "  This does not appear to be a Drupal project." >&2
  echo "  Use --force to skip this check." >&2
  exit 1
else
  echo "  ${GREEN}✓ Drupal project detected${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 1 — Copy .claude/ directory (skills, hooks, settings)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 1: Installing .claude/ directory${RESET}"

# --- settings.json ---
install_file \
  "$TEMPLATE_DIR/.claude/settings.json" \
  "$TARGET_DIR/.claude/settings.json"

# --- hooks ---
install_file_executable \
  "$TEMPLATE_DIR/.claude/hooks/post-generation-lint.sh" \
  "$TARGET_DIR/.claude/hooks/post-generation-lint.sh"

install_file \
  "$TEMPLATE_DIR/.claude/hooks/README.md" \
  "$TARGET_DIR/.claude/hooks/README.md"

# --- skills ---
# Walk every file under .claude/skills/ in the template and replicate it.
while IFS= read -r src_file; do
  # Compute the path relative to the template .claude/ directory.
  relative="${src_file#"$TEMPLATE_DIR"/.claude/}"
  install_file "$src_file" "$TARGET_DIR/.claude/$relative"
done < <(find "$TEMPLATE_DIR/.claude/skills" -type f | sort)

# ═══════════════════════════════════════════════════════════════════════════
# Phase 2 — Append Drupal rules to CLAUDE.md (or create from template)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 2: CLAUDE.md${RESET}"

if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  # CLAUDE.md exists (e.g. from `claude /init`) — append Drupal rules if not already present.
  if grep -q '<!-- drupal-agentic-workflow -->' "$TARGET_DIR/CLAUDE.md"; then
    log_up_to_date "CLAUDE.md (Drupal rules already present)"
    UP_TO_DATE=$((UP_TO_DATE + 1))
  else
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "CLAUDE.md (appended Drupal rules) (dry-run)"
    else
      # Append: separator + marker + template content (skip first 3 lines: title + instruction + blank)
      {
        echo ""
        echo "<!-- drupal-agentic-workflow -->"
        echo ""
        tail -n +4 "$TEMPLATE_DIR/CLAUDE-TEMPLATE.md"
      } >> "$TARGET_DIR/CLAUDE.md"
      log_installed "CLAUDE.md (appended Drupal rules)"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
else
  # No CLAUDE.md at all — create from template.
  if [[ "$DRY_RUN" == true ]]; then
    log_installed "CLAUDE.md (from CLAUDE-TEMPLATE.md) (dry-run)"
  else
    cp "$TEMPLATE_DIR/CLAUDE-TEMPLATE.md" "$TARGET_DIR/CLAUDE.md"
    log_installed "CLAUDE.md (from CLAUDE-TEMPLATE.md)"
  fi
  INSTALLED=$((INSTALLED + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 3 — Install .prettierrc.json (if missing)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 3: .prettierrc.json${RESET}"

install_file \
  "$TEMPLATE_DIR/.prettierrc.json" \
  "$TARGET_DIR/.prettierrc.json"

# ═══════════════════════════════════════════════════════════════════════════
# Phase 4 — AI_CONTEXT.md for custom modules
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 4: AI_CONTEXT.md for custom modules${RESET}"

CUSTOM_MODULES_DIR="$TARGET_DIR/web/modules/custom"

if [[ -d "$CUSTOM_MODULES_DIR" ]]; then
  MODULE_COUNT=0

  for module_dir in "$CUSTOM_MODULES_DIR"/*/; do
    # Skip if the glob didn't match anything (no subdirectories).
    [[ -d "$module_dir" ]] || continue

    module_machine_name="$(basename "$module_dir")"
    ai_context_file="$module_dir/AI_CONTEXT.md"

    if [[ -f "$ai_context_file" ]]; then
      log_up_to_date "web/modules/custom/$module_machine_name/AI_CONTEXT.md"
      UP_TO_DATE=$((UP_TO_DATE + 1))
      MODULE_COUNT=$((MODULE_COUNT + 1))
      continue
    fi

    # Try to extract the human-readable name from the .info.yml file.
    info_yml="$module_dir/${module_machine_name}.info.yml"
    module_human_name="$module_machine_name"
    module_dependencies=""

    if [[ -f "$info_yml" ]]; then
      # Extract "name:" value (first match).
      yml_name="$(grep -m1 '^name:' "$info_yml" 2>/dev/null | sed "s/^name:[[:space:]]*//" | sed "s/^['\"]//;s/['\"]$//" || true)"
      if [[ -n "$yml_name" ]]; then
        module_human_name="$yml_name"
      fi

      # Extract dependencies (lines under "dependencies:").
      if grep -q '^dependencies:' "$info_yml" 2>/dev/null; then
        module_dependencies="$(awk '/^dependencies:/{found=1; next} found && /^[[:space:]]+- /{print $2; next} found{exit}' "$info_yml" 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || true)"
      fi
    fi

    # Fill in dependencies placeholder.
    if [[ -z "$module_dependencies" ]]; then
      deps_text="{list from .info.yml if readable}"
    else
      deps_text="$module_dependencies"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      log_installed "web/modules/custom/$module_machine_name/AI_CONTEXT.md (dry-run)"
    else
      cat > "$ai_context_file" <<AIEOF
# ${module_human_name} — AI Context

> Generated by drupal-agentic-workflow setup. Fill in the sections below.

## Purpose
{Describe what this module does}

## Architecture
- **Type**: Custom module
- **Dependencies**: ${deps_text}

## Key Files
| File | Purpose |
|------|---------|
| ${module_machine_name}.module | Hook implementations |

## Data Flow
{Document the main data flow}
AIEOF
      log_installed "web/modules/custom/$module_machine_name/AI_CONTEXT.md"
    fi
    INSTALLED=$((INSTALLED + 1))
    MODULE_COUNT=$((MODULE_COUNT + 1))
  done

  if [[ "$MODULE_COUNT" -eq 0 ]]; then
    echo "  ${GRAY}No custom modules found in web/modules/custom/${RESET}"
  fi
else
  echo "  ${GRAY}Directory not found: web/modules/custom/ — skipping${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 5 — Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════"
echo "  drupal-agentic-workflow — Setup Complete"
if [[ "$DRY_RUN" == true ]]; then
  echo "  ${YELLOW}(DRY RUN — no files were modified)${RESET}"
fi
echo "══════════════════════════════════════════════"
echo ""
echo "  ${GREEN}Installed${RESET} : ${INSTALLED} files"
echo "  ${GRAY}Up to date${RESET}: ${UP_TO_DATE} files"
echo "  ${YELLOW}Skipped${RESET}   : ${SKIPPED} files (customized, not overwritten)"
echo ""
echo "  Next steps:"
echo "  1. Review CLAUDE.md and fill in project details"
echo "  2. List your custom modules in the \"Custom Modules\" section"
echo "  3. List installed contrib modules in the \"Contributed Modules\" section"
echo "  4. Review AI_CONTEXT.md files in web/modules/custom/*/"
echo ""
echo "══════════════════════════════════════════════"
echo ""
