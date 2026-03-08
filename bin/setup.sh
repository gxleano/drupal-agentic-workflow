#!/usr/bin/env bash
#
# setup.sh — Install drupal-agentic-workflow into a target Drupal project.
#
# Usage: bin/setup.sh [TARGET_DIR] [OPTIONS]
#   TARGET_DIR    Path to a Drupal project root (default: current directory)
#   --force       Skip Drupal project detection
#   --dry-run     Show what would be done without making changes
#   --skip-tools  Skip code quality tools detection/installation
#   --help        Show this help message
#
# Phases:
#   0. Validate target is a Drupal project (composer.json with drupal/core)
#   1. Check and install code quality tools (phpcs, phpstan)
#   2. Copy .claude/ directory (skills, hooks, settings)
#   3. Append Drupal rules to CLAUDE.md (or create from template)
#   4. Install .prettierrc.json (if missing)
#   5. Scan web/modules/custom/ and create AI_CONTEXT.md templates for modules missing one
#   6. Print summary with counts and next steps
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
SKIP_TOOLS=false

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
  --skip-tools  Skip code quality tools detection/installation
  --help        Show this help message

Phases:
  0. Validate target is a Drupal project (composer.json with drupal/core)
  1. Check and install code quality tools (phpcs, phpstan)
  2. Copy .claude/ directory (skills, hooks, settings)
  3. Append Drupal rules to CLAUDE.md (or create from template)
  4. Install .prettierrc.json (if missing)
  5. Scan web/modules/custom/ and create AI_CONTEXT.md templates
  6. Print summary with counts and next steps
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
    --skip-tools)
      SKIP_TOOLS=true
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
# Phase 1 — Code Quality Tools
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 1: Code Quality Tools${RESET}"

if [[ "$SKIP_TOOLS" == true ]]; then
  echo "  ${YELLOW}--skip-tools: skipping code quality tools check${RESET}"
else
  # --- Check host: jq ---
  if command -v jq &>/dev/null; then
    echo "  ${GREEN}✓ jq installed${RESET} (required by hooks)"
  else
    echo "  ${YELLOW}⚠ jq not found${RESET} — required by hooks for JSON parsing" >&2
    echo "    Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  fi

  # --- Check composer.json for code quality packages ---
  if [[ -f "$TARGET_DIR/composer.json" ]]; then
    MISSING_REQUIRED=()
    MISSING_RECOMMENDED=()

    # Required: drupal/coder (provides phpcs Drupal/DrupalPractice standards)
    if grep -q '"drupal/coder"' "$TARGET_DIR/composer.json" 2>/dev/null; then
      echo "  ${GREEN}✓ drupal/coder${RESET} (phpcs Drupal standards)"
    else
      MISSING_REQUIRED+=("drupal/coder")
      echo "  ${YELLOW}✗ drupal/coder${RESET} — REQUIRED for phpcs Drupal/DrupalPractice standards"
    fi

    # Recommended: phpstan packages
    if grep -q '"phpstan/phpstan"' "$TARGET_DIR/composer.json" 2>/dev/null; then
      echo "  ${GREEN}✓ phpstan/phpstan${RESET}"
    else
      MISSING_RECOMMENDED+=("phpstan/phpstan")
      echo "  ${GRAY}○ phpstan/phpstan${RESET} (recommended)"
    fi

    if grep -q '"mglaman/phpstan-drupal"' "$TARGET_DIR/composer.json" 2>/dev/null; then
      echo "  ${GREEN}✓ mglaman/phpstan-drupal${RESET}"
    else
      MISSING_RECOMMENDED+=("mglaman/phpstan-drupal")
      echo "  ${GRAY}○ mglaman/phpstan-drupal${RESET} (recommended)"
    fi

    if grep -q '"phpstan/phpstan-deprecation-rules"' "$TARGET_DIR/composer.json" 2>/dev/null; then
      echo "  ${GREEN}✓ phpstan/phpstan-deprecation-rules${RESET}"
    else
      MISSING_RECOMMENDED+=("phpstan/phpstan-deprecation-rules")
      echo "  ${GRAY}○ phpstan/phpstan-deprecation-rules${RESET} (recommended)"
    fi

    # --- Prompt to install missing required packages ---
    if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
      echo ""
      echo "  ${YELLOW}Missing required packages: ${MISSING_REQUIRED[*]}${RESET}"
      if [[ "$DRY_RUN" == true ]]; then
        echo "  ${GRAY}(dry-run) Would prompt to install: ddev composer require --dev ${MISSING_REQUIRED[*]}${RESET}"
      else
        echo -n "  Install via ddev composer require --dev? [Y/n] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
          echo "  Installing ${MISSING_REQUIRED[*]}..."
          if ddev composer require --dev "${MISSING_REQUIRED[@]}" 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ Required packages installed${RESET}"
          else
            echo "  ${YELLOW}⚠ Installation failed — install manually:${RESET}" >&2
            echo "    ddev composer require --dev ${MISSING_REQUIRED[*]}" >&2
          fi
        else
          echo "  ${GRAY}Skipped. Install manually:${RESET}"
          echo "    ddev composer require --dev ${MISSING_REQUIRED[*]}"
        fi
      fi
    fi

    # --- Prompt to install missing recommended packages ---
    if [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
      echo ""
      echo "  ${GRAY}Missing recommended packages: ${MISSING_RECOMMENDED[*]}${RESET}"
      if [[ "$DRY_RUN" == true ]]; then
        echo "  ${GRAY}(dry-run) Would prompt to install: ddev composer require --dev ${MISSING_RECOMMENDED[*]}${RESET}"
      else
        echo -n "  Install recommended packages via ddev composer? [y/N] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
          echo "  Installing ${MISSING_RECOMMENDED[*]}..."
          if ddev composer require --dev "${MISSING_RECOMMENDED[@]}" 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ Recommended packages installed${RESET}"
          else
            echo "  ${YELLOW}⚠ Installation failed — install manually:${RESET}" >&2
            echo "    ddev composer require --dev ${MISSING_RECOMMENDED[*]}" >&2
          fi
        else
          echo "  ${GRAY}Skipped. Install manually when ready:${RESET}"
          echo "    ddev composer require --dev ${MISSING_RECOMMENDED[*]}"
        fi
      fi
    fi
  fi

  # --- Generate phpstan.neon if missing ---
  PHPSTAN_NEON="$TARGET_DIR/phpstan.neon"
  if [[ -f "$PHPSTAN_NEON" ]]; then
    echo ""
    echo "  ${GREEN}✓ phpstan.neon exists${RESET}"
  else
    if [[ "$DRY_RUN" == true ]]; then
      echo ""
      log_installed "phpstan.neon (dry-run)"
    else
      cat > "$PHPSTAN_NEON" <<'PHPSTAN'
parameters:
  level: 2
  paths:
    - web/modules/custom
  drupal:
    drupal_root: web
PHPSTAN
      echo ""
      log_installed "phpstan.neon"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 2 — Copy .claude/ directory (skills, hooks, settings)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 2: Installing .claude/ directory${RESET}"

# --- settings.json ---
install_file \
  "$TEMPLATE_DIR/.claude/settings.json" \
  "$TARGET_DIR/.claude/settings.json"

# --- hooks ---
install_file_executable \
  "$TEMPLATE_DIR/.claude/hooks/pre-bash-guard.sh" \
  "$TARGET_DIR/.claude/hooks/pre-bash-guard.sh"

install_file_executable \
  "$TEMPLATE_DIR/.claude/hooks/post-generation-lint.sh" \
  "$TARGET_DIR/.claude/hooks/post-generation-lint.sh"

install_file_executable \
  "$TEMPLATE_DIR/.claude/hooks/prompt-context.sh" \
  "$TARGET_DIR/.claude/hooks/prompt-context.sh"

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
# Phase 3 — Merge Drupal rules into CLAUDE.md
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 3: CLAUDE.md${RESET}"

START_MARKER="<!-- drupal-agentic-workflow:start -->"
END_MARKER="<!-- drupal-agentic-workflow:end -->"
OLD_MARKER="<!-- drupal-agentic-workflow -->"

# Template content: skip first 5 lines (title, instruction, blank, blank, ---).
TEMPLATE_CONTENT=$(tail -n +6 "$TEMPLATE_DIR/CLAUDE-TEMPLATE.md")

# Project-specific scaffold — added once, never replaced by updates.
PROJECT_SCAFFOLD=$(cat <<'SCAFFOLD'

## Custom Modules

Located in `web/modules/custom/`. Each module has an `AI_CONTEXT.md` file — **read it first** before exploring module code.

<!-- List your custom modules here. Example format:
- **my_module**: Brief description — [AI_CONTEXT.md](web/modules/custom/my_module/AI_CONTEXT.md)
-->

## Installed Contributed Modules/Themes

<!-- List your installed contrib modules/themes here. Example format:
- **drupal/gin** ^5.0: Modern admin theme
- **drupal/token** ^1.17: Token support
-->

## NEVER Commit

- `web/sites/default/settings.local.php`
- `.ddev/.env` or any secret values
- `vendor/` directory
SCAFFOLD
)

# Helper: write the managed block (markers + template content).
write_managed_block() {
  echo "$START_MARKER"
  echo ""
  echo "$TEMPLATE_CONTENT"
  echo ""
  echo "$END_MARKER"
}

if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  if grep -qF "$START_MARKER" "$TARGET_DIR/CLAUDE.md"; then
    # ── New markers found: replace content between them ──────────────
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "CLAUDE.md (updated managed rules) (dry-run)"
    else
      TEMP_FILE=$(mktemp)
      TEMPLATE_FILE=$(mktemp)
      write_managed_block > "$TEMPLATE_FILE"

      awk -v start="$START_MARKER" -v end="$END_MARKER" -v tmpl="$TEMPLATE_FILE" '
        $0 == start {
          while ((getline line < tmpl) > 0) print line
          close(tmpl)
          skip = 1
          next
        }
        $0 == end {
          skip = 0
          next
        }
        !skip { print }
      ' "$TARGET_DIR/CLAUDE.md" > "$TEMP_FILE"

      mv "$TEMP_FILE" "$TARGET_DIR/CLAUDE.md"
      rm -f "$TEMPLATE_FILE"
      log_installed "CLAUDE.md (updated managed rules)"
    fi
    INSTALLED=$((INSTALLED + 1))

  elif grep -qF "$OLD_MARKER" "$TARGET_DIR/CLAUDE.md"; then
    # ── Old single marker: migrate to new dual-marker format ─────────
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "CLAUDE.md (migrated to managed markers) (dry-run)"
    else
      TEMP_FILE=$(mktemp)

      # Keep everything BEFORE the old marker.
      sed -n "/$OLD_MARKER/q;p" "$TARGET_DIR/CLAUDE.md" > "$TEMP_FILE"

      # Append new managed block + project scaffold.
      {
        echo ""
        write_managed_block
        echo "$PROJECT_SCAFFOLD"
      } >> "$TEMP_FILE"

      mv "$TEMP_FILE" "$TARGET_DIR/CLAUDE.md"
      log_installed "CLAUDE.md (migrated to managed markers)"
      echo "  ${YELLOW}⚠ Old Drupal rules replaced. If you customized the Custom Modules or" >&2
      echo "    Contrib Modules sections, re-add them from git diff.${RESET}" >&2
    fi
    INSTALLED=$((INSTALLED + 1))

  else
    # ── No markers: append managed block + project scaffold ──────────
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "CLAUDE.md (appended Drupal rules) (dry-run)"
    else
      {
        echo ""
        write_managed_block
        echo "$PROJECT_SCAFFOLD"
      } >> "$TARGET_DIR/CLAUDE.md"
      log_installed "CLAUDE.md (appended Drupal rules)"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
else
  # ── No CLAUDE.md: create from scratch ────────────────────────────────
  if [[ "$DRY_RUN" == true ]]; then
    log_installed "CLAUDE.md (created with Drupal rules) (dry-run)"
  else
    {
      echo "# CLAUDE.md"
      echo ""
      write_managed_block
      echo "$PROJECT_SCAFFOLD"
    } > "$TARGET_DIR/CLAUDE.md"
    log_installed "CLAUDE.md (created with Drupal rules)"
  fi
  INSTALLED=$((INSTALLED + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 4 — Install .prettierrc.json (if missing)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 4: .prettierrc.json${RESET}"

install_file \
  "$TEMPLATE_DIR/.prettierrc.json" \
  "$TARGET_DIR/.prettierrc.json"

# ═══════════════════════════════════════════════════════════════════════════
# Phase 5 — AI_CONTEXT.md for custom modules
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 5: AI_CONTEXT.md for custom modules${RESET}"

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
# Phase 6 — Summary
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
