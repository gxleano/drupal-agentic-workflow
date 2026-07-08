#!/usr/bin/env bash
#
# setup.sh — Install drupal-agentic-workflow into a target Drupal project.
#
# Usage: bin/setup.sh [TARGET_DIR] [OPTIONS]
#   TARGET_DIR    Path to a Drupal project root (default: current directory)
#   --force       Skip Drupal project detection
#   --dry-run     Show what would be done without making changes
#   --skip-tools       Skip code quality tools detection/installation
#   --skip-ai-context  Skip AI_CONTEXT.md generation prompt
#   --skip-detect      Skip stack detection / skill gap analysis
#   --skip-followups   Skip the interactive "open claude for X" prompts at the end
#   --help             Show this help message
#
# Phases:
#   0. Validate target is a Drupal project (composer.json with drupal/core)
#   1. Check and install code quality tools (phpcs, phpstan)
#   2. Copy .claude/ directory (skills, hooks, settings)
#   3. Append Drupal rules to CLAUDE.md (or create from template)
#   4. Install .prettierrc.json (if missing)
#   5. (Optional) Analyze web/modules/custom/ and generate AI_CONTEXT.md with real module info
#   6. Update CLAUDE.md Custom Modules section with discovered modules
#   7. Detect stack (PHP/Drupal/frontend) and report skill capability gaps
#   7b. Write .claude/skills-recommended.md mapping capabilities → skills
#   7c. Scan custom code for convention adoption; write .claude/conventions.md
#   7d. Scaffold knowledge files (ADRs, glossary, external systems, fixtures)
#   7e. Build project-map.md from Drupal config + custom module YAMLs
#   7f. Render version-aware Drupal guide → .claude/drupal-version-guide.md
#   7g. Vendor matching Examples module checkout → .claude/reference/examples/
#   7h. Maintain managed .gitignore block
#   7i. Build live site-API index (Drush) → .claude/site-api.json
#   8. Print summary with counts and next steps
#   9. Offer interactive `claude` follow-ups for CLAUDE.md / AI_CONTEXT polish
#
# Idempotency rules:
#   - File exists and matches source → "up to date"
#   - File exists and differs → "SKIPPED (customized)" — never overwrite user changes
#   - File missing → copy and log "installed"

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve TEMPLATE_DIR: the root of the drupal-agentic-workflow repository.
# This script lives at bin/setup.sh, so the template root is one level up.
# Follow symlinks so the script still resolves its package root when invoked
# through Composer's vendor/bin (e.g. vendor/bin/daw → bin/setup.sh). Portable:
# avoids `readlink -f`, which is absent on macOS.
# ---------------------------------------------------------------------------
_daw_src="${BASH_SOURCE[0]}"
while [[ -h "$_daw_src" ]]; do
  _daw_dir="$(cd -P "$(dirname "$_daw_src")" >/dev/null 2>&1 && pwd)"
  _daw_src="$(readlink "$_daw_src")"
  [[ "$_daw_src" != /* ]] && _daw_src="$_daw_dir/$_daw_src"
done
TEMPLATE_DIR="$(cd -P "$(dirname "$_daw_src")/.." >/dev/null 2>&1 && pwd)"
unset _daw_src _daw_dir

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

# Per-artifact status flags consumed by the Phase 8 summary. Set by Phase 7f
# (version guide), 7g (Examples checkout), 7h (gitignore managed block), and
# 7i (live site-API index).
VERSION_GUIDE_STATUS="skipped"
EXAMPLES_STATUS="skipped"
GITIGNORE_STATUS="skipped"
SITE_API_STATUS="skipped"

# ---------------------------------------------------------------------------
# Flags / defaults
# ---------------------------------------------------------------------------
TARGET_DIR=""
FORCE=false
DRY_RUN=false
SKIP_TOOLS=false
SKIP_AI_CONTEXT=false
SKIP_DETECT=false
SKIP_FOLLOWUPS=false

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
  --skip-tools       Skip code quality tools detection/installation
  --skip-ai-context  Skip AI_CONTEXT.md generation prompt
  --skip-detect      Skip stack detection / skill gap analysis
  --skip-followups   Skip the interactive "open claude for X" prompts at the end
  --help             Show this help message

Phases:
  0. Validate target is a Drupal project (composer.json with drupal/core)
  1. Check and install code quality tools (phpcs, phpstan)
  2. Copy .claude/ directory (skills, hooks, settings)
  3. Append Drupal rules to CLAUDE.md (or create from template)
  4. Install .prettierrc.json (if missing)
  5. (Optional) Analyze custom modules and generate AI_CONTEXT.md files
  6. Update CLAUDE.md Custom Modules section with discovered modules
  7. Detect stack and report skill capability gaps
  7b. Write .claude/skills-recommended.md mapping capabilities → skills
  7c. Scan custom code for convention adoption; write .claude/conventions.md
  7d. Scaffold knowledge files (ADRs, glossary, external systems, fixtures)
  7e. Build project-map.md (content types, roles, routes, services, splits)
  7f. Render version-aware Drupal guide (.claude/drupal-version-guide.md)
  7g. Vendor matching Examples checkout (.claude/reference/examples/)
  7h. Maintain managed .gitignore block
  7i. Build live site-API index via Drush (.claude/site-api.json)
  8. Print summary with counts and next steps
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
    --skip-ai-context)
      SKIP_AI_CONTEXT=true
      shift
      ;;
    --skip-detect)
      SKIP_DETECT=true
      shift
      ;;
    --skip-followups)
      SKIP_FOLLOWUPS=true
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

# Sub-bullet note — used for secondary edits to a file already counted in
# INSTALLED/UP_TO_DATE this run (e.g., the version-guide pointer appended
# alongside the main CLAUDE.md merge). Does not affect counters.
log_note() {
  echo "    ${GRAY}↳${RESET} $1"
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
    elif [[ "$FORCE" == true ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log_installed "$relative_dest (forced, dry-run)"
      else
        cp "$src" "$dest"
        log_installed "$relative_dest (forced)"
      fi
      INSTALLED=$((INSTALLED + 1))
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
    elif [[ "$FORCE" == true ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log_installed "$relative_dest (forced, dry-run)"
      else
        cp "$src" "$dest"
        chmod +x "$dest"
        log_installed "$relative_dest (forced)"
      fi
      INSTALLED=$((INSTALLED + 1))
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

# ---------------------------------------------------------------------------
# Helper: examples_branch_for_major MAJOR
#
# Returns the branch name of the Drupal Examples module that corresponds to
# the given Drupal core major version. Echoes empty string for unmapped
# majors — callers should `warn` and skip when that happens.
#
# MAINTAINER NOTE: When a new Drupal major ships, check the Examples project
# page at https://www.drupal.org/project/examples for the supported branch
# and add a new case below.
# ---------------------------------------------------------------------------
examples_branch_for_major() {
  local major="$1"
  # Strip any Composer constraint operator / non-digits ("^11.0" → "11") so
  # the mapping is robust whether the caller passes a clean major or a raw
  # constraint string.
  major="${major//[^0-9]/}"
  case "$major" in
    10) echo "4.0.x" ;;
    11) echo "4.0.x" ;;
    *)  echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Helper: warn — write a yellow warning to stderr.
# ---------------------------------------------------------------------------
warn() {
  echo "  ${YELLOW}⚠${RESET} $*" >&2
}

# ---------------------------------------------------------------------------
# Helper: update_gitignore_managed_block GITIGNORE_PATH
#
# Idempotently maintain a managed block in a `.gitignore` (or any text file)
# delimited by:
#
#     # >>> drupal-agentic-workflow >>>
#     ...
#     # <<< drupal-agentic-workflow <<<
#
# The block is reconciled — required lines (defined below) are added if
# missing, but any extra lines a user has added inside the block are kept
# in place. Lines OUTSIDE the markers are never touched.
#
# Respects $DRY_RUN. Updates $INSTALLED / $UP_TO_DATE accordingly.
#
# Echoes one of: "installed", "up-to-date", "dry-run-installed",
# "dry-run-up-to-date" — callers can capture for Phase 8 summary state.
# ---------------------------------------------------------------------------
GITIGNORE_BLOCK_START="# >>> drupal-agentic-workflow >>>"
GITIGNORE_BLOCK_END="# <<< drupal-agentic-workflow <<<"
GITIGNORE_REQUIRED_LINES=(
  "web/modules/custom/**/AI_CONTEXT.md"
  ".claude/reference/"
  ".claude/site-api.json"
)

update_gitignore_managed_block() {
  local gitignore="$1"
  local relative="${gitignore#"$TARGET_DIR"/}"
  local need_required=()
  local kept_extras=()
  local in_block=0
  local has_block=0

  if [[ -f "$gitignore" ]] && grep -qF "$GITIGNORE_BLOCK_START" "$gitignore"; then
    has_block=1
    # Read the existing block contents, separating required vs extra lines.
    local existing_block=()
    while IFS= read -r line; do
      if [[ "$line" == "$GITIGNORE_BLOCK_START" ]]; then
        in_block=1
        continue
      fi
      if [[ "$line" == "$GITIGNORE_BLOCK_END" ]]; then
        in_block=0
        continue
      fi
      if [[ "$in_block" == 1 ]]; then
        existing_block+=("$line")
      fi
    done < "$gitignore"

    # Identify required lines already present and any extra (user) lines.
    local req
    for line in "${existing_block[@]+"${existing_block[@]}"}"; do
      local is_required=0
      for req in "${GITIGNORE_REQUIRED_LINES[@]}"; do
        if [[ "$line" == "$req" ]]; then
          is_required=1
          break
        fi
      done
      if [[ "$is_required" == 0 ]]; then
        kept_extras+=("$line")
      fi
    done

    # Determine which required lines are missing.
    for req in "${GITIGNORE_REQUIRED_LINES[@]}"; do
      local found=0
      for line in "${existing_block[@]+"${existing_block[@]}"}"; do
        if [[ "$line" == "$req" ]]; then
          found=1
          break
        fi
      done
      if [[ "$found" == 0 ]]; then
        need_required+=("$req")
      fi
    done
  else
    # File missing the block entirely — every required line is "missing".
    need_required=("${GITIGNORE_REQUIRED_LINES[@]}")
  fi

  # If the block already exists and no required lines are missing, we're done.
  if [[ "$has_block" == 1 && ${#need_required[@]} -eq 0 ]]; then
    log_up_to_date "$relative (managed block)"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    GITIGNORE_STATUS="up-to-date"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$has_block" == 1 ]]; then
      log_installed "$relative (reconciled managed block) (dry-run)"
    else
      log_installed "$relative (added managed block) (dry-run)"
    fi
    INSTALLED=$((INSTALLED + 1))
    GITIGNORE_STATUS="installed"
    return 0
  fi

  mkdir -p "$(dirname "$gitignore")"

  if [[ "$has_block" == 1 ]]; then
    # Rebuild block in place: required lines (in canonical order), then
    # any extra user-added lines preserved as-is.
    local tmp tmp_body
    tmp=$(mktemp)
    tmp_body=$(mktemp)
    {
      for req in "${GITIGNORE_REQUIRED_LINES[@]}"; do
        echo "$req"
      done
      for extra in "${kept_extras[@]+"${kept_extras[@]}"}"; do
        echo "$extra"
      done
    } > "$tmp_body"

    awk -v start="$GITIGNORE_BLOCK_START" -v end="$GITIGNORE_BLOCK_END" \
        -v body_file="$tmp_body" '
      BEGIN { skip = 0 }
      $0 == start {
        print start
        while ((getline line < body_file) > 0) print line
        close(body_file)
        print end
        skip = 1
        next
      }
      $0 == end {
        if (skip == 1) { skip = 0; next }
        print
        next
      }
      !skip { print }
    ' "$gitignore" > "$tmp"

    mv "$tmp" "$gitignore"
    rm -f "$tmp_body"
    log_installed "$relative (reconciled managed block)"
  else
    # No block present (file may or may not exist) — append it.
    {
      if [[ -f "$gitignore" && -n "$(tail -c1 "$gitignore" 2>/dev/null)" ]]; then
        echo ""
      fi
      if [[ -s "$gitignore" ]]; then
        echo ""
      fi
      echo "$GITIGNORE_BLOCK_START"
      for req in "${GITIGNORE_REQUIRED_LINES[@]}"; do
        echo "$req"
      done
      echo "$GITIGNORE_BLOCK_END"
    } >> "$gitignore"
    log_installed "$relative (added managed block)"
  fi
  INSTALLED=$((INSTALLED + 1))
  GITIGNORE_STATUS="installed"
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
  # Resolve composer + drush runners the same way Phase 7i / the lint hooks do:
  # prefer DDEV, else fall back to host binaries so non-DDEV projects (make, etc.) work.
  # Assumes TARGET_DIR has no spaces; arrays keep flags safe regardless.
  if command -v ddev &>/dev/null && [[ -f "$TARGET_DIR/.ddev/config.yaml" ]]; then
    COMPOSER_RUN=(ddev composer)
    DRUSH_RUN=(ddev drush)
  else
    COMPOSER_RUN=(composer "--working-dir=$TARGET_DIR")
    if [[ -x "$TARGET_DIR/vendor/bin/drush" ]]; then
      DRUSH_RUN=("$TARGET_DIR/vendor/bin/drush")
    else
      DRUSH_RUN=(drush)
    fi
  fi
  COMPOSER_HINT="${COMPOSER_RUN[*]}"
  DRUSH_HINT="${DRUSH_RUN[*]}"

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

    # Composer 2.2+ blocks third-party plugins unless allow-listed. The Drupal
    # quality stack (drupal/coder → phpcodesniffer-composer-installer) and
    # drush_dtk's deps pull this plugin in, so every `composer require` below
    # aborts until it's allowed. Self-heal it first.
    CS_PLUGIN="dealerdirect/phpcodesniffer-composer-installer"
    if ! jq -e --arg p "$CS_PLUGIN" \
        '(.config["allow-plugins"] == true) or (.config["allow-plugins"][$p] == true)' \
        "$TARGET_DIR/composer.json" >/dev/null 2>&1; then
      if [[ "$DRY_RUN" == true ]]; then
        echo "  ${GRAY}(dry-run) Would allow Composer plugin: $CS_PLUGIN${RESET}"
      else
        echo "  ${YELLOW}⚠ Composer plugin not allow-listed: $CS_PLUGIN${RESET}"
        echo "    Required by drupal/coder and drush_dtk; composer require fails without it."
        echo -n "  Allow it? [Y/n] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
          if "${COMPOSER_RUN[@]}" config --no-plugins "allow-plugins.$CS_PLUGIN" true 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ allowed $CS_PLUGIN${RESET}"
          else
            echo "  ${YELLOW}⚠ Failed — set manually:${RESET} $COMPOSER_HINT config allow-plugins.$CS_PLUGIN true" >&2
          fi
        else
          echo "  ${GRAY}Skipped — composer installs below will likely fail.${RESET}"
        fi
      fi
    fi

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
        echo "  ${GRAY}(dry-run) Would prompt to install: $COMPOSER_HINT require --dev ${MISSING_REQUIRED[*]}${RESET}"
      else
        echo -n "  Install via $COMPOSER_HINT require --dev? [Y/n] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
          echo "  Installing ${MISSING_REQUIRED[*]}..."
          if "${COMPOSER_RUN[@]}" require --dev "${MISSING_REQUIRED[@]}" 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ Required packages installed${RESET}"
          else
            echo "  ${YELLOW}⚠ Installation failed — install manually:${RESET}" >&2
            echo "    $COMPOSER_HINT require --dev ${MISSING_REQUIRED[*]}" >&2
          fi
        else
          echo "  ${GRAY}Skipped. Install manually:${RESET}"
          echo "    $COMPOSER_HINT require --dev ${MISSING_REQUIRED[*]}"
        fi
      fi
    fi

    # --- Prompt to install missing recommended packages ---
    if [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
      echo ""
      echo "  ${GRAY}Missing recommended packages: ${MISSING_RECOMMENDED[*]}${RESET}"
      if [[ "$DRY_RUN" == true ]]; then
        echo "  ${GRAY}(dry-run) Would prompt to install: $COMPOSER_HINT require --dev ${MISSING_RECOMMENDED[*]}${RESET}"
      else
        echo -n "  Install recommended packages via $COMPOSER_HINT? [y/N] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
          echo "  Installing ${MISSING_RECOMMENDED[*]}..."
          if "${COMPOSER_RUN[@]}" require --dev "${MISSING_RECOMMENDED[@]}" 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ Recommended packages installed${RESET}"
          else
            echo "  ${YELLOW}⚠ Installation failed — install manually:${RESET}" >&2
            echo "    $COMPOSER_HINT require --dev ${MISSING_RECOMMENDED[*]}" >&2
          fi
        else
          echo "  ${GRAY}Skipped. Install manually when ready:${RESET}"
          echo "    $COMPOSER_HINT require --dev ${MISSING_RECOMMENDED[*]}"
        fi
      fi
    fi

    # --- Optional: ivanboring/drush_dtk (Drush Token Killer), dev-only ---
    # Compresses verbose Drush output (pm:list, config:status, …) by 45–97% to
    # cut tokens for AI agents. Ships no composer.json, so it needs an inline
    # "package" repository before it can be required.
    DTK_PKG='{"type":"package","package":{"name":"ivanboring/drush_dtk","version":"dev-main","type":"drupal-module","source":{"url":"https://github.com/ivanboring/drush_dtk.git","type":"git","reference":"main"}}}'
    if jq -e '.["require-dev"]["ivanboring/drush_dtk"] // empty' "$TARGET_DIR/composer.json" >/dev/null 2>&1; then
      echo "  ${GREEN}✓ ivanboring/drush_dtk${RESET} (Drush output compression)"
    elif [[ "$DRY_RUN" == true ]]; then
      echo "  ${GRAY}(dry-run) Would offer to install ivanboring/drush_dtk (dev-only Drush Token Killer)${RESET}"
    else
      echo ""
      echo "  ${GRAY}○ ivanboring/drush_dtk${RESET} — dev-only Drush output compression for AI agents"
      echo -n "  Install drush_dtk (dev-only) and enable it? [Y/n] "
      read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
      if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
        echo "  Installing ivanboring/drush_dtk..."
        if "${COMPOSER_RUN[@]}" config repositories.drush_dtk "$DTK_PKG" 2>&1 | sed 's/^/    /' \
          && "${COMPOSER_RUN[@]}" require --dev -W "ivanboring/drush_dtk:dev-main" 2>&1 | sed 's/^/    /'; then
          echo "  ${GREEN}✓ drush_dtk installed${RESET}"
          if "${DRUSH_RUN[@]}" en drush_dtk -y 2>&1 | sed 's/^/    /'; then
            echo "  ${GREEN}✓ drush_dtk enabled${RESET} — keep it out of exported config (it's dev-only)"
          else
            echo "  ${YELLOW}⚠ Enable manually:${RESET} $DRUSH_HINT en drush_dtk -y" >&2
          fi
        else
          echo "  ${YELLOW}⚠ Installation failed — install manually:${RESET}" >&2
          echo "    $COMPOSER_HINT config repositories.drush_dtk '$DTK_PKG'" >&2
          echo "    $COMPOSER_HINT require --dev -W ivanboring/drush_dtk:dev-main" >&2
        fi
      else
        echo "  ${GRAY}Skipped.${RESET}"
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
  "$TEMPLATE_DIR/.claude/hooks/post-session-phpstan.sh" \
  "$TARGET_DIR/.claude/hooks/post-session-phpstan.sh"

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

# Render the shared template (skipping its 5-line maintainer header), dropping
# the block family meant for the *other* agent. CLAUDE.md keeps the Claude-only
# Skills Reference; AGENTS.md keeps the agent-agnostic "Detailed patterns"
# pointer. One source of truth (CLAUDE-TEMPLATE.md) → two renders, no drift.
#   $1 = marker family to DROP: "claude-only" | "agents-only"
render_template_dropping() {
  local drop="daw:$1"
  tail -n +6 "$TEMPLATE_DIR/CLAUDE-TEMPLATE.md" | awk -v drop="$drop" '
    index($0, "<!-- " drop ":start -->") { skip = 1; next }
    index($0, "<!-- " drop ":end -->")   { skip = 0; next }
    # Strip the kept family'\''s own marker lines (keep their content).
    /<!-- daw:(claude|agents)-only:(start|end) -->/ { next }
    !skip { print }
  '
}

# CLAUDE.md gets the Claude-only block; AGENTS.md gets the agent-agnostic one.
TEMPLATE_CONTENT=$(render_template_dropping agents-only)
AGENTS_CONTENT=$(render_template_dropping claude-only)

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

## Project Lessons

<!-- This section is yours — it lives outside the managed block and is never overwritten by setup.sh updates.
     When Claude makes a mistake you correct, add it here so it won't repeat across sessions.

     Format: - <rule> (learned YYYY-MM-DD)
     Examples:
     - Don't use X library for Y — use Z instead (learned 2025-03-01)
     - Our API returns paginated results — always handle the _links.next cursor (learned 2025-03-15)
-->
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

# Idempotently upsert a START/END managed block into an arbitrary file.
# Replaces content between markers if present, appends if the file exists
# without markers, or creates the file (with an optional header) if missing.
# Used for AGENTS.md; CLAUDE.md keeps its own richer merge logic below.
#   $1 = target file   $2 = block content
#   $3 = log label     $4 = header line for newly-created files (optional)
upsert_managed_block() {
  local file="$1" content="$2" label="$3" header="${4:-}"
  local block tmp
  block="$(printf '%s\n\n%s\n\n%s\n' "$START_MARKER" "$content" "$END_MARKER")"

  if [[ -f "$file" ]] && grep -qF "$START_MARKER" "$file"; then
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "$label (updated managed block) (dry-run)"
    else
      tmp=$(mktemp)
      local blockfile; blockfile=$(mktemp)
      printf '%s\n' "$block" > "$blockfile"
      awk -v start="$START_MARKER" -v end="$END_MARKER" -v tmpl="$blockfile" '
        $0 == start { while ((getline line < tmpl) > 0) print line; close(tmpl); skip = 1; next }
        $0 == end   { skip = 0; next }
        !skip { print }
      ' "$file" > "$tmp"
      mv "$tmp" "$file"; rm -f "$blockfile"
      log_installed "$label (updated managed block)"
    fi
  elif [[ -f "$file" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "$label (appended managed block) (dry-run)"
    else
      { echo ""; printf '%s\n' "$block"; } >> "$file"
      log_installed "$label (appended managed block)"
    fi
  else
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "$label (created) (dry-run)"
    else
      { [[ -n "$header" ]] && { printf '%s\n\n' "$header"; }; printf '%s\n' "$block"; } > "$file"
      log_installed "$label (created)"
    fi
  fi
  INSTALLED=$((INSTALLED + 1))
}

# ---------------------------------------------------------------------------
# Version-guide pointer block — idempotently injected into CLAUDE.md so the
# coding agent always sees a one-line reference to the per-version Drupal
# guide rendered by Phase 7f. The marker comment lets future setup.sh runs
# locate and rewrite the line without duplicating.
# ---------------------------------------------------------------------------
VERSION_GUIDE_POINTER_MARKER="<!-- drupal-agentic-workflow: version-guide-pointer -->"
VERSION_GUIDE_POINTER_LINE="See \`.claude/drupal-version-guide.md\` for version-specific patterns; prefer it over generic Drupal advice."

ensure_version_guide_pointer() {
  local claude_md="$TARGET_DIR/CLAUDE.md"
  [[ -f "$claude_md" ]] || return 0

  if grep -qF "$VERSION_GUIDE_POINTER_MARKER" "$claude_md"; then
    # Marker present: extract the line directly below it and compare.
    local current_line
    current_line="$(awk -v m="$VERSION_GUIDE_POINTER_MARKER" '
      $0 == m { getline nxt; print nxt; exit }
    ' "$claude_md")"

    if [[ "$current_line" == "$VERSION_GUIDE_POINTER_LINE" ]]; then
      log_note "version-guide pointer up to date"
      return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
      log_note "would refresh version-guide pointer (dry-run)"
      return 0
    fi

    # Rewrite the marker + the immediately following line atomically.
    local tmp
    tmp=$(mktemp)
    awk -v marker="$VERSION_GUIDE_POINTER_MARKER" -v line="$VERSION_GUIDE_POINTER_LINE" '
      $0 == marker {
        print marker
        print line
        # Drop the next line (the stale pointer text).
        getline _drop
        next
      }
      { print }
    ' "$claude_md" > "$tmp"
    mv "$tmp" "$claude_md"
    log_note "refreshed version-guide pointer"
    return 0
  fi

  # Marker missing: append the pointer block to the end of the file.
  if [[ "$DRY_RUN" == true ]]; then
    log_note "would add version-guide pointer (dry-run)"
    return 0
  fi

  {
    # Ensure file ends with a newline before appending a separating blank line.
    if [[ -n "$(tail -c1 "$claude_md")" ]]; then
      echo ""
    fi
    echo ""
    echo "$VERSION_GUIDE_POINTER_MARKER"
    echo "$VERSION_GUIDE_POINTER_LINE"
  } >> "$claude_md"
  log_note "added version-guide pointer"
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

# Inject (or refresh) the one-line pointer to the per-version Drupal guide
# that Phase 7f renders. This extends the CLAUDE.md merge step — it must
# stay attached to Phase 3 so the pointer exists regardless of detection.
ensure_version_guide_pointer

# ═══════════════════════════════════════════════════════════════════════════
# Phase 3b — Emit AGENTS.md for non-Claude agents (Cursor, Codex, Gemini, …)
# ═══════════════════════════════════════════════════════════════════════════
# AGENTS.md is the cross-agent instruction file convention. It carries the same
# agent-agnostic Drupal rules and knowledge-file index as CLAUDE.md's managed
# block, minus the Claude-specific Skill-tool routing (replaced by a pointer to
# read the SKILL.md files as plain docs). Rendered from the same template.
echo ""
echo "${BOLD}Phase 3b: AGENTS.md${RESET}"

AGENTS_HEADER="# AGENTS.md

Cross-agent instructions for this Drupal project. Claude Code reads \`CLAUDE.md\`;
this file is for other AI coding agents (Cursor, Codex, Gemini CLI, Copilot, …).
The block below is managed by drupal-agentic-workflow and refreshed on re-run —
add your own project notes outside the markers."

upsert_managed_block \
  "$TARGET_DIR/AGENTS.md" \
  "$AGENTS_CONTENT" \
  "AGENTS.md" \
  "$AGENTS_HEADER"

# ═══════════════════════════════════════════════════════════════════════════
# Phase 4 — Install .prettierrc.json (if missing)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 4: .prettierrc.json${RESET}"

install_file \
  "$TEMPLATE_DIR/.prettierrc.json" \
  "$TARGET_DIR/.prettierrc.json"

# ═══════════════════════════════════════════════════════════════════════════
# Phase 5 — AI_CONTEXT.md for custom modules (interactive)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 5: AI_CONTEXT.md for custom modules${RESET}"

CUSTOM_MODULES_DIR="$TARGET_DIR/web/modules/custom"
# Track discovered modules for Phase 6 (CLAUDE.md Custom Modules section).
DISCOVERED_MODULES=()

# ---------------------------------------------------------------------------
# Helper: analyze_module DIR MACHINE_NAME
#
# Reads the module's actual files and generates AI_CONTEXT.md with real info.
# ---------------------------------------------------------------------------
analyze_module() {
  local module_dir="$1"
  local machine_name="$2"
  local info_yml="$module_dir/${machine_name}.info.yml"

  # ── Extract info.yml metadata ──────────────────────────────────────────
  local human_name="$machine_name"
  local description=""
  local module_type="Custom module"
  local package=""
  local dependencies=""

  if [[ -f "$info_yml" ]]; then
    human_name="$(grep -m1 '^name:' "$info_yml" 2>/dev/null \
      | sed "s/^name:[[:space:]]*//" | sed "s/^['\"]//;s/['\"]$//" || true)"
    [[ -z "$human_name" ]] && human_name="$machine_name"

    description="$(grep -m1 '^description:' "$info_yml" 2>/dev/null \
      | sed "s/^description:[[:space:]]*//" | sed "s/^['\"]//;s/['\"]$//" || true)"

    package="$(grep -m1 '^package:' "$info_yml" 2>/dev/null \
      | sed "s/^package:[[:space:]]*//" | sed "s/^['\"]//;s/['\"]$//" || true)"

    if grep -q '^dependencies:' "$info_yml" 2>/dev/null; then
      dependencies="$(awk '/^dependencies:/{found=1; next} found && /^[[:space:]]+- /{print $2; next} found{exit}' \
        "$info_yml" 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || true)"
    fi
  fi

  # ── Scan for key files and structures ──────────────────────────────────
  local has_module_file=false
  local has_routing=false
  local has_services=false
  local has_permissions=false
  local has_libraries=false
  local has_install=false
  local has_config_install=false
  local has_config_schema=false
  local has_templates=false

  [[ -f "$module_dir/${machine_name}.module" ]] && has_module_file=true
  [[ -f "$module_dir/${machine_name}.routing.yml" ]] && has_routing=true
  [[ -f "$module_dir/${machine_name}.services.yml" ]] && has_services=true
  [[ -f "$module_dir/${machine_name}.permissions.yml" ]] && has_permissions=true
  [[ -f "$module_dir/${machine_name}.libraries.yml" ]] && has_libraries=true
  [[ -f "$module_dir/${machine_name}.install" ]] && has_install=true
  [[ -d "$module_dir/config/install" ]] && has_config_install=true
  [[ -d "$module_dir/config/schema" ]] && has_config_schema=true
  [[ -d "$module_dir/templates" ]] && has_templates=true

  # ── Extract hooks from .module ─────────────────────────────────────────
  local hooks_list=""
  if [[ "$has_module_file" == true ]]; then
    hooks_list="$(grep -oP "^function ${machine_name}_\K[a-z_]+" \
      "$module_dir/${machine_name}.module" 2>/dev/null | head -20 || true)"
  fi

  # ── Extract routes ─────────────────────────────────────────────────────
  local routes_list=""
  if [[ "$has_routing" == true ]]; then
    routes_list="$(grep -E '^[a-zA-Z_][a-zA-Z0-9_.]*:' \
      "$module_dir/${machine_name}.routing.yml" 2>/dev/null | sed 's/:$//' | head -15 || true)"
  fi

  # ── Extract services ───────────────────────────────────────────────────
  local services_list=""
  if [[ "$has_services" == true ]]; then
    services_list="$(grep -E '^  [a-zA-Z_][a-zA-Z0-9_.]*:' \
      "$module_dir/${machine_name}.services.yml" 2>/dev/null \
      | sed 's/^  //;s/:$//' | head -15 || true)"
  fi

  # ── Discover src/ structure (plugins, forms, controllers, etc.) ────────
  local src_summary=""
  if [[ -d "$module_dir/src" ]]; then
    local src_dirs
    src_dirs="$(find "$module_dir/src" -type d -mindepth 1 | sort)"
    if [[ -n "$src_dirs" ]]; then
      src_summary=""
      while IFS= read -r dir; do
        local relative_dir="${dir#"$module_dir"/src/}"
        local file_count
        file_count="$(find "$dir" -maxdepth 1 -name '*.php' -type f 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$file_count" -gt 0 ]]; then
          src_summary="${src_summary}\n- \`src/${relative_dir}/\` — ${file_count} PHP file(s)"
        fi
      done <<< "$src_dirs"
    fi
  fi

  # ── Extract permissions ────────────────────────────────────────────────
  local permissions_list=""
  if [[ "$has_permissions" == true ]]; then
    permissions_list="$(grep -E '^[a-z_][a-z_ ]*:' \
      "$module_dir/${machine_name}.permissions.yml" 2>/dev/null \
      | sed "s/['\"]//g;s/:$//" | head -10 || true)"
  fi

  # ── Build the AI_CONTEXT.md content ────────────────────────────────────
  local content=""
  content="# ${human_name} — AI Context"
  content="${content}

> Auto-generated by drupal-agentic-workflow setup from module analysis."

  # Purpose section
  if [[ -n "$description" ]]; then
    content="${content}

## Purpose
${description}"
  else
    content="${content}

## Purpose
<!-- TODO: Describe what this module does -->"
  fi

  # Architecture section
  content="${content}

## Architecture
- **Machine name**: \`${machine_name}\`"
  [[ -n "$package" ]] && content="${content}
- **Package**: ${package}"
  content="${content}
- **Type**: ${module_type}"
  if [[ -n "$dependencies" ]]; then
    content="${content}
- **Dependencies**: ${dependencies}"
  else
    content="${content}
- **Dependencies**: None"
  fi

  # Key Files table
  content="${content}

## Key Files
| File | Purpose |
|------|---------|"

  [[ "$has_module_file" == true ]] && content="${content}
| \`${machine_name}.module\` | Hook implementations |"
  [[ "$has_routing" == true ]] && content="${content}
| \`${machine_name}.routing.yml\` | Route definitions |"
  [[ "$has_services" == true ]] && content="${content}
| \`${machine_name}.services.yml\` | Service definitions |"
  [[ "$has_permissions" == true ]] && content="${content}
| \`${machine_name}.permissions.yml\` | Permission definitions |"
  [[ "$has_libraries" == true ]] && content="${content}
| \`${machine_name}.libraries.yml\` | CSS/JS library definitions |"
  [[ "$has_install" == true ]] && content="${content}
| \`${machine_name}.install\` | Install/update hooks |"
  [[ "$has_config_install" == true ]] && content="${content}
| \`config/install/\` | Default configuration |"
  [[ "$has_config_schema" == true ]] && content="${content}
| \`config/schema/\` | Configuration schema |"
  [[ "$has_templates" == true ]] && content="${content}
| \`templates/\` | Twig templates |"

  # Source structure
  if [[ -n "$src_summary" ]]; then
    content="${content}

## Source Structure"
    content="${content}$(echo -e "$src_summary")"
  fi

  # Hooks
  if [[ -n "$hooks_list" ]]; then
    content="${content}

## Hooks Implemented"
    while IFS= read -r hook; do
      content="${content}
- \`hook_${hook}()\`"
    done <<< "$hooks_list"
  fi

  # Routes
  if [[ -n "$routes_list" ]]; then
    content="${content}

## Routes"
    while IFS= read -r route; do
      content="${content}
- \`${route}\`"
    done <<< "$routes_list"
  fi

  # Services
  if [[ -n "$services_list" ]]; then
    content="${content}

## Services"
    while IFS= read -r service; do
      content="${content}
- \`${service}\`"
    done <<< "$services_list"
  fi

  # Permissions
  if [[ -n "$permissions_list" ]]; then
    content="${content}

## Permissions"
    while IFS= read -r perm; do
      content="${content}
- \`${perm}\`"
    done <<< "$permissions_list"
  fi

  echo "$content"
}

if [[ "$SKIP_AI_CONTEXT" == true ]]; then
  echo "  ${YELLOW}--skip-ai-context: skipping AI_CONTEXT.md generation${RESET}"
elif [[ ! -d "$CUSTOM_MODULES_DIR" ]]; then
  echo "  ${GRAY}Directory not found: web/modules/custom/ — skipping${RESET}"
else
  # Count modules and check which already have AI_CONTEXT.md.
  MODULES_TOTAL=0
  MODULES_MISSING_CONTEXT=0
  for module_dir in "$CUSTOM_MODULES_DIR"/*/; do
    [[ -d "$module_dir" ]] || continue
    MODULES_TOTAL=$((MODULES_TOTAL + 1))
    module_machine_name="$(basename "$module_dir")"
    DISCOVERED_MODULES+=("$module_machine_name")
    if [[ ! -f "$module_dir/AI_CONTEXT.md" ]]; then
      MODULES_MISSING_CONTEXT=$((MODULES_MISSING_CONTEXT + 1))
    fi
  done

  if [[ "$MODULES_TOTAL" -eq 0 ]]; then
    echo "  ${GRAY}No custom modules found in web/modules/custom/${RESET}"
  elif [[ "$MODULES_MISSING_CONTEXT" -eq 0 ]]; then
    echo "  All ${MODULES_TOTAL} module(s) already have AI_CONTEXT.md"
    for module_dir in "$CUSTOM_MODULES_DIR"/*/; do
      [[ -d "$module_dir" ]] || continue
      module_machine_name="$(basename "$module_dir")"
      log_up_to_date "web/modules/custom/$module_machine_name/AI_CONTEXT.md"
      UP_TO_DATE=$((UP_TO_DATE + 1))
    done
  else
    echo "  Found ${MODULES_TOTAL} custom module(s), ${MODULES_MISSING_CONTEXT} missing AI_CONTEXT.md"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
      echo "  ${GRAY}(dry-run) Would prompt to generate AI_CONTEXT.md files${RESET}"
      GENERATE_AI_CONTEXT=true
    else
      echo -n "  Generate AI_CONTEXT.md by analyzing module files? [Y/n] "
      read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
      if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
        GENERATE_AI_CONTEXT=true
      else
        GENERATE_AI_CONTEXT=false
        echo "  ${GRAY}Skipped. You can generate these later by re-running setup.${RESET}"
      fi
    fi

    if [[ "$GENERATE_AI_CONTEXT" == true ]]; then
      for module_dir in "$CUSTOM_MODULES_DIR"/*/; do
        [[ -d "$module_dir" ]] || continue
        module_machine_name="$(basename "$module_dir")"
        ai_context_file="$module_dir/AI_CONTEXT.md"

        if [[ -f "$ai_context_file" ]]; then
          log_up_to_date "web/modules/custom/$module_machine_name/AI_CONTEXT.md"
          UP_TO_DATE=$((UP_TO_DATE + 1))
          continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
          log_installed "web/modules/custom/$module_machine_name/AI_CONTEXT.md (dry-run)"
        else
          echo "  Analyzing $module_machine_name..."
          ai_content="$(analyze_module "$module_dir" "$module_machine_name")"
          echo "$ai_content" > "$ai_context_file"
          log_installed "web/modules/custom/$module_machine_name/AI_CONTEXT.md"
        fi
        INSTALLED=$((INSTALLED + 1))
      done
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 6 — Update CLAUDE.md Custom Modules section with discovered modules
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 6: Updating CLAUDE.md Custom Modules listing${RESET}"

if [[ ${#DISCOVERED_MODULES[@]} -gt 0 && -f "$TARGET_DIR/CLAUDE.md" ]]; then
  # Build the module listing.
  MODULE_LISTING=""
  for mod in "${DISCOVERED_MODULES[@]}"; do
    info_yml="$CUSTOM_MODULES_DIR/$mod/${mod}.info.yml"
    mod_desc=""
    if [[ -f "$info_yml" ]]; then
      mod_desc="$(grep -m1 '^description:' "$info_yml" 2>/dev/null \
        | sed "s/^description:[[:space:]]*//" | sed "s/^['\"]//;s/['\"]$//" || true)"
    fi
    if [[ -n "$mod_desc" ]]; then
      MODULE_LISTING="${MODULE_LISTING}- **${mod}**: ${mod_desc} — [AI_CONTEXT.md](web/modules/custom/${mod}/AI_CONTEXT.md)
"
    else
      MODULE_LISTING="${MODULE_LISTING}- **${mod}** — [AI_CONTEXT.md](web/modules/custom/${mod}/AI_CONTEXT.md)
"
    fi
  done

  # Check if the Custom Modules section has the placeholder comment.
  if grep -qF '<!-- List your custom modules here.' "$TARGET_DIR/CLAUDE.md"; then
    if [[ "$DRY_RUN" == true ]]; then
      log_installed "CLAUDE.md (Custom Modules listing) (dry-run)"
    else
      # Replace the placeholder comment block with the actual module listing.
      TEMP_FILE=$(mktemp)
      LISTING_FILE=$(mktemp)
      printf '%s' "$MODULE_LISTING" > "$LISTING_FILE"
      awk -v listing_file="$LISTING_FILE" '
        /<!-- List your custom modules here\./ {
          while ($0 !~ /-->/) { if ((getline) <= 0) break }
          while ((getline line < listing_file) > 0) print line
          close(listing_file)
          next
        }
        { print }
      ' "$TARGET_DIR/CLAUDE.md" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$TARGET_DIR/CLAUDE.md"
      rm -f "$LISTING_FILE"
      log_installed "CLAUDE.md (Custom Modules listing)"
    fi
    INSTALLED=$((INSTALLED + 1))
  else
    echo "  ${GRAY}Custom Modules section already customized — not overwriting${RESET}"
  fi
else
  echo "  ${GRAY}No modules to list or CLAUDE.md not found — skipping${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7 — Stack detection and skill capability gap analysis
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7: Stack detection${RESET}"

DETECT_SRC="$TEMPLATE_DIR/assets/tools/detect.mjs"
DETECT_DEST="$TARGET_DIR/.claude/tools/detect.mjs"

if [[ "$SKIP_DETECT" == true ]]; then
  echo "  ${YELLOW}--skip-detect: skipping stack detection${RESET}"
elif [[ ! -f "$DETECT_SRC" ]]; then
  echo "  ${YELLOW}⚠ detect.mjs not found in template (${DETECT_SRC#"$TEMPLATE_DIR"/})${RESET}"
elif ! command -v node &>/dev/null; then
  install_file "$DETECT_SRC" "$DETECT_DEST"
  echo "  ${YELLOW}⚠ node not found — install Node 18+ then run: node .claude/tools/detect.mjs${RESET}"
else
  install_file "$DETECT_SRC" "$DETECT_DEST"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would run: node .claude/tools/detect.mjs --gaps${RESET}"
  else
    echo "  Running detect.mjs..."
    if (cd "$TARGET_DIR" && node .claude/tools/detect.mjs --gaps >/dev/null 2>&1); then
      STACK_JSON="$TARGET_DIR/.claude/stack.json"

      if command -v jq &>/dev/null && [[ -f "$STACK_JSON" ]]; then
        echo ""
        echo "  ${BOLD}Detected stack:${RESET}"
        jq -r '
          "    Backend     : " + (.backend.framework // "n/a") + " " + (.backend.drupal_core // "") + " / PHP " + (.backend.php_version // "n/a"),
          "    Frontend    : " + ((.frontend.languages // []) | join("+")) + " via " + (.frontend.build // "n/a") + " (node " + (.frontend.node // "n/a") + ")",
          "    Modules     : " + ((.backend.custom_modules_count // 0) | tostring) + " custom",
          "    Integrations: " + (((.backend.integrations // []) | join(", ")) // "none")
        ' "$STACK_JSON"

        OK_COUNT=$(jq -r '[.skills.capabilities[] | select(.status == "available")] | length' "$STACK_JSON")
        GAP_COUNT=$(jq -r '.skills.gaps | length' "$STACK_JSON")
        echo ""
        echo "  ${BOLD}Skill capabilities:${RESET}"
        echo "    ${GREEN}✓ satisfied${RESET}: $OK_COUNT"
        echo "    ${YELLOW}⚠ gaps${RESET}     : $GAP_COUNT"

        if [[ "$GAP_COUNT" -gt 0 ]]; then
          echo ""
          echo "  Capabilities without an available skill:"
          jq -r '.skills.gaps[] | "    - \(.capability) [\(.status)]"' "$STACK_JSON"
        fi

        DRIFT_COUNT=$(jq -r '.drift | length' "$STACK_JSON")
        if [[ "$DRIFT_COUNT" -gt 0 ]]; then
          echo ""
          echo "  ${YELLOW}Drift warnings:${RESET}"
          jq -r '.drift[] | "    ⚠ \(.)"' "$STACK_JSON"
        fi

        echo ""
        echo "  Full report : .claude/stack.json"
        echo "  Gap summary : .claude/gaps.md"
      else
        echo "  ${GREEN}✓ Wrote .claude/stack.json and .claude/gaps.md${RESET}"
        echo "  ${GRAY}(install jq for a formatted summary)${RESET}"
      fi
    else
      echo "  ${YELLOW}⚠ Stack detection failed — run manually: node .claude/tools/detect.mjs --print${RESET}" >&2
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7f — Render the version-specific Drupal guide
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7f: Drupal version guide${RESET}"

VERSION_GUIDE_DEST="$TARGET_DIR/.claude/drupal-version-guide.md"
VERSION_GUIDE_STACK_JSON="$TARGET_DIR/.claude/stack.json"

if [[ ! -f "$VERSION_GUIDE_STACK_JSON" ]]; then
  echo "  ${GRAY}No stack.json found (detection skipped or failed) — skipping${RESET}"
else
  # Read backend.drupal_core; prefer jq, fall back to grep/sed (mirrors 7g).
  VG_DRUPAL_CORE=""
  if command -v jq &>/dev/null; then
    VG_DRUPAL_CORE="$(jq -r '.backend.drupal_core // ""' "$VERSION_GUIDE_STACK_JSON" 2>/dev/null || echo "")"
  else
    VG_DRUPAL_CORE="$(grep -o '"drupal_core"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_GUIDE_STACK_JSON" 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")"
  fi

  if [[ -z "$VG_DRUPAL_CORE" ]]; then
    warn "Could not determine Drupal core version from stack.json — skipping version guide render"
  else
    # Derive major and minor (e.g. "10.3.5" → major=10, minor=3).
    VG_MAJOR="${VG_DRUPAL_CORE%%.*}"
    VG_REST="${VG_DRUPAL_CORE#*.}"
    VG_MINOR="${VG_REST%%.*}"
    # Guard against drupal_core values like "10" (no minor segment).
    if [[ "$VG_MINOR" == "$VG_DRUPAL_CORE" ]]; then
      VG_MINOR=""
    fi

    # Select template directory by major.minor when available, else fall back.
    VG_TEMPLATE_REL=""
    case "$VG_MAJOR" in
      10)
        case "$VG_MINOR" in
          3) VG_TEMPLATE_REL="assets/knowledge/drupal/10.3/guide.md" ;;
          4) VG_TEMPLATE_REL="assets/knowledge/drupal/10.4/guide.md" ;;
          *)
            VG_TEMPLATE_REL="assets/knowledge/drupal/10.4/guide.md"
            warn "No exact match for Drupal $VG_DRUPAL_CORE — falling back to 10.4 guide"
            ;;
        esac
        ;;
      11)
        VG_TEMPLATE_REL="assets/knowledge/drupal/11.x/guide.md"
        ;;
      12)
        VG_TEMPLATE_REL="assets/knowledge/drupal/11.x/guide.md"
        warn "No guide for Drupal $VG_DRUPAL_CORE yet — falling back to 11.x guide"
        ;;
      *)
        VG_TEMPLATE_REL="assets/knowledge/drupal/11.x/guide.md"
        warn "Unrecognized Drupal major '$VG_MAJOR' — falling back to 11.x guide"
        ;;
    esac

    VG_TEMPLATE_SRC="$TEMPLATE_DIR/$VG_TEMPLATE_REL"

    if [[ ! -f "$VG_TEMPLATE_SRC" ]]; then
      warn "Version guide template not found at ${VG_TEMPLATE_REL} — skipping"
    else
      # Determine action: force re-render, fresh install, up-to-date, or refresh.
      VG_NEEDS_WRITE=false
      if [[ ! -f "$VERSION_GUIDE_DEST" ]]; then
        VG_NEEDS_WRITE=true
      elif [[ "$FORCE" == true ]]; then
        VG_NEEDS_WRITE=true
      elif ! cmp -s "$VG_TEMPLATE_SRC" "$VERSION_GUIDE_DEST"; then
        VG_NEEDS_WRITE=true
      fi

      if [[ "$VG_NEEDS_WRITE" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          log_installed ".claude/drupal-version-guide.md (from ${VG_TEMPLATE_REL#assets/knowledge/drupal/}) (dry-run)"
          INSTALLED=$((INSTALLED + 1))
        else
          mkdir -p "$(dirname "$VERSION_GUIDE_DEST")"
          cp "$VG_TEMPLATE_SRC" "$VERSION_GUIDE_DEST"
          log_installed ".claude/drupal-version-guide.md (from ${VG_TEMPLATE_REL#assets/knowledge/drupal/})"
          INSTALLED=$((INSTALLED + 1))
        fi
        VERSION_GUIDE_STATUS="installed (Drupal $VG_DRUPAL_CORE)"
      else
        log_up_to_date ".claude/drupal-version-guide.md (Drupal $VG_DRUPAL_CORE)"
        UP_TO_DATE=$((UP_TO_DATE + 1))
        VERSION_GUIDE_STATUS="up-to-date (Drupal $VG_DRUPAL_CORE)"
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7g — Vendor the Drupal Examples module into .claude/reference/examples
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7g: Reference: Drupal Examples module${RESET}"

EXAMPLES_DIR="$TARGET_DIR/.claude/reference/examples"
EXAMPLES_MARKER="$EXAMPLES_DIR/.fetched-for"
REFERENCE_README="$TARGET_DIR/.claude/reference/README.md"
STACK_JSON="$TARGET_DIR/.claude/stack.json"

if ! command -v git &>/dev/null; then
  warn "git not found on PATH — skipping examples vendor (non-fatal)"
elif [[ ! -f "$STACK_JSON" ]]; then
  echo "  ${GRAY}No stack.json found (detection skipped or failed) — skipping${RESET}"
else
  # Prefer the normalized backend.drupal_major emitted by detect.mjs; fall
  # back to backend.drupal_core for stack.json files written before that
  # field existed. Prefer jq, fall back to grep/sed.
  DRUPAL_MAJOR=""
  DRUPAL_CORE=""
  if command -v jq &>/dev/null; then
    DRUPAL_MAJOR="$(jq -r '.backend.drupal_major // ""' "$STACK_JSON" 2>/dev/null || echo "")"
    DRUPAL_CORE="$(jq -r '.backend.drupal_core // ""' "$STACK_JSON" 2>/dev/null || echo "")"
  else
    DRUPAL_MAJOR="$(grep -o '"drupal_major"[[:space:]]*:[[:space:]]*[0-9]*' "$STACK_JSON" 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/' || echo "")"
    DRUPAL_CORE="$(grep -o '"drupal_core"[[:space:]]*:[[:space:]]*"[^"]*"' "$STACK_JSON" 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")"
  fi

  # Fall back to parsing drupal_core, sanitizing to digits only so constraint
  # strings like "^11.0" or "~10.3" still yield a clean major ("11"/"10").
  if [[ -z "$DRUPAL_MAJOR" || "$DRUPAL_MAJOR" == "null" ]]; then
    DRUPAL_MAJOR="${DRUPAL_CORE%%.*}"
    DRUPAL_MAJOR="${DRUPAL_MAJOR//[^0-9]/}"
  fi

  if [[ -z "$DRUPAL_MAJOR" ]]; then
    warn "Could not determine Drupal major from stack.json — skipping examples vendor"
  else
    EXAMPLES_BRANCH="$(examples_branch_for_major "$DRUPAL_MAJOR")"
    if [[ -z "$EXAMPLES_BRANCH" ]]; then
      warn "No Examples branch mapping for Drupal $DRUPAL_MAJOR — update examples_branch_for_major() in bin/setup.sh"
    else
      # Determine current fetched-for state.
      FETCHED_MAJOR=""
      if [[ -f "$EXAMPLES_MARKER" ]]; then
        FETCHED_MAJOR="$(grep -o '"drupal_major"[[:space:]]*:[[:space:]]*"[^"]*"' "$EXAMPLES_MARKER" 2>/dev/null \
          | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")"
      fi

      NEEDS_CLONE=false
      if [[ ! -d "$EXAMPLES_DIR" ]]; then
        NEEDS_CLONE=true
      elif [[ "$FORCE" == true ]]; then
        NEEDS_CLONE=true
      elif [[ -z "$FETCHED_MAJOR" || "$FETCHED_MAJOR" != "$DRUPAL_MAJOR" ]]; then
        NEEDS_CLONE=true
      fi

      if [[ "$NEEDS_CLONE" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          log_installed ".claude/reference/examples (branch $EXAMPLES_BRANCH for Drupal $DRUPAL_MAJOR) (dry-run)"
          INSTALLED=$((INSTALLED + 1))
        else
          # Wipe any stale checkout (different major / partial clone).
          if [[ -d "$EXAMPLES_DIR" ]]; then
            rm -rf "$EXAMPLES_DIR"
          fi
          mkdir -p "$(dirname "$EXAMPLES_DIR")"
          echo "  Cloning Drupal Examples module (branch $EXAMPLES_BRANCH for Drupal $DRUPAL_MAJOR)..."
          if git clone --depth=1 --branch="$EXAMPLES_BRANCH" \
              https://git.drupalcode.org/project/examples.git "$EXAMPLES_DIR" 2>&1 | sed 's/^/    /'; then
            FETCH_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            cat > "$EXAMPLES_MARKER" <<MARKER
{
  "drupal_major": "$DRUPAL_MAJOR",
  "branch": "$EXAMPLES_BRANCH",
  "fetch_date": "$FETCH_DATE"
}
MARKER
            log_installed ".claude/reference/examples (branch $EXAMPLES_BRANCH for Drupal $DRUPAL_MAJOR)"
            INSTALLED=$((INSTALLED + 1))
            EXAMPLES_STATUS="installed (branch $EXAMPLES_BRANCH, Drupal $DRUPAL_MAJOR)"
          else
            warn "git clone of Drupal Examples module failed — skipping"
            EXAMPLES_STATUS="failed (git clone error)"
          fi
        fi
        [[ "$DRY_RUN" == true ]] && EXAMPLES_STATUS="installed (branch $EXAMPLES_BRANCH, Drupal $DRUPAL_MAJOR)"
      else
        log_up_to_date ".claude/reference/examples (Drupal $DRUPAL_MAJOR, branch $EXAMPLES_BRANCH)"
        UP_TO_DATE=$((UP_TO_DATE + 1))
        EXAMPLES_STATUS="up-to-date (branch $EXAMPLES_BRANCH, Drupal $DRUPAL_MAJOR)"
      fi

      # Install reference README once (idempotent).
      if [[ -f "$REFERENCE_README" ]]; then
        log_up_to_date ".claude/reference/README.md"
        UP_TO_DATE=$((UP_TO_DATE + 1))
      else
        if [[ "$DRY_RUN" == true ]]; then
          log_installed ".claude/reference/README.md (dry-run)"
          INSTALLED=$((INSTALLED + 1))
        else
          mkdir -p "$(dirname "$REFERENCE_README")"
          cat > "$REFERENCE_README" <<'REFREADME'
# .claude/reference/

Read-only canonical Drupal patterns vendored for the coding agent.

## Rules

- **Read-only**: never modify files under this directory by hand.
- **Never enable**: these modules are reference material only — do not
  install or enable them in the Drupal site.
- **Never copy verbatim**: study the patterns and adapt them to the
  project's own conventions (`.claude/conventions.md`) and naming.
- **Refreshed by setup.sh**: re-running `bin/setup.sh` re-clones these
  when the Drupal major changes. Use `--force` to force a refresh.

## Note

This directory is gitignored. It exists only on local checkouts after
running setup.sh, not in the repository.
REFREADME
          log_installed ".claude/reference/README.md"
          INSTALLED=$((INSTALLED + 1))
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7h — Patch project .gitignore with a managed block
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7h: .gitignore managed block${RESET}"

update_gitignore_managed_block "$TARGET_DIR/.gitignore"

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7b — Write recommended-skills doc from detector output
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7b: Recommended skills${RESET}"

RECO_FILE="$TARGET_DIR/.claude/skills-recommended.md"
STACK_JSON="$TARGET_DIR/.claude/stack.json"

if [[ "$SKIP_DETECT" == true ]]; then
  echo "  ${YELLOW}--skip-detect: skipping recommended-skills doc${RESET}"
elif [[ ! -f "$STACK_JSON" ]]; then
  echo "  ${GRAY}No stack.json found (detection skipped or failed) — skipping${RESET}"
elif ! command -v jq &>/dev/null; then
  echo "  ${YELLOW}⚠ jq required to build recommended-skills doc — skipping${RESET}"
else
  # Build the recommended-skills markdown into a temp file.
  RECO_TMP=$(mktemp)
  {
    PROJECT_NAME=$(jq -r '.project.name // "project"' "$STACK_JSON")
    echo "# Recommended skills for ${PROJECT_NAME}"
    echo ""
    echo "> Generated by drupal-agentic-workflow setup."
    echo "> Source of truth: \`.claude/stack.json\` (check mtime for freshness)."
    echo "> Re-run \`setup.sh\` to refresh."
    echo ""
    echo "## Detected stack"
    echo ""
    jq -r '
      "- **Backend**: " + (.backend.framework // "n/a") + " " + (.backend.drupal_core // "") + " on PHP " + (.backend.php_version // "n/a"),
      "- **Frontend**: " + ((.frontend.languages // []) | join(", ")) + " via " + (.frontend.build // "n/a") + " (node " + (.frontend.node // "n/a") + ")",
      "- **Custom modules**: " + ((.backend.custom_modules_count // 0) | tostring),
      "- **Integrations**: " + (if ((.backend.integrations // []) | length) > 0 then ((.backend.integrations // []) | join(", ")) else "none" end)
    ' "$STACK_JSON"
    echo ""
    echo "## Use these skills for this project"
    echo ""
    echo "| Capability | Skill | When to invoke |"
    echo "|------------|-------|----------------|"
    jq -r '
      .skills.capabilities[]
      | select(.status == "available")
      | . as $cap
      | .satisfied_by[]
      | "| `\($cap.capability)` | `\(.name)` | " + (if (.description // "") != "" then .description else "when working on \($cap.capability) concerns" end) + " |"
    ' "$STACK_JSON"
    echo ""
    GAP_COUNT=$(jq -r '.skills.gaps | length' "$STACK_JSON")
    if [[ "$GAP_COUNT" -gt 0 ]]; then
      echo "## Capability gaps (no canonical skill yet)"
      echo ""
      jq -r '.skills.gaps[] | "- **\(.capability)** — \(.status)"' "$STACK_JSON"
      echo ""
      echo "These are project-specific needs without an installed skill. Consider scaffolding one under \`.claude/skills/\` if the gap is recurring."
      echo ""
    fi
    DRIFT_COUNT=$(jq -r '.drift | length' "$STACK_JSON")
    if [[ "$DRIFT_COUNT" -gt 0 ]]; then
      echo "## Drift warnings"
      echo ""
      jq -r '.drift[] | "- \(.)"' "$STACK_JSON"
      echo ""
    fi
  } > "$RECO_TMP"

  # Apply standard idempotency rules.
  if [[ -f "$RECO_FILE" ]]; then
    if diff -q "$RECO_TMP" "$RECO_FILE" &>/dev/null; then
      log_up_to_date ".claude/skills-recommended.md"
      UP_TO_DATE=$((UP_TO_DATE + 1))
      rm -f "$RECO_TMP"
    else
      if [[ "$DRY_RUN" == true ]]; then
        log_skipped ".claude/skills-recommended.md"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$RECO_TMP"
      else
        echo -n "  Existing .claude/skills-recommended.md differs. Overwrite? [y/N] "
        read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
          mv "$RECO_TMP" "$RECO_FILE"
          log_installed ".claude/skills-recommended.md (refreshed)"
          INSTALLED=$((INSTALLED + 1))
        else
          log_skipped ".claude/skills-recommended.md"
          SKIPPED=$((SKIPPED + 1))
          rm -f "$RECO_TMP"
        fi
      fi
    fi
  else
    if [[ "$DRY_RUN" == true ]]; then
      log_installed ".claude/skills-recommended.md (dry-run)"
      rm -f "$RECO_TMP"
    else
      mv "$RECO_TMP" "$RECO_FILE"
      log_installed ".claude/skills-recommended.md"
    fi
    INSTALLED=$((INSTALLED + 1))
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7c — Convention scan (mine existing code for adopted idioms)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7c: Convention scan${RESET}"

CONV_SRC="$TEMPLATE_DIR/assets/tools/conventions.mjs"
CONV_DEST="$TARGET_DIR/.claude/tools/conventions.mjs"

if [[ "$SKIP_DETECT" == true ]]; then
  echo "  ${YELLOW}--skip-detect: skipping convention scan${RESET}"
elif [[ ! -f "$CONV_SRC" ]]; then
  echo "  ${YELLOW}⚠ conventions.mjs not found in template${RESET}"
elif ! command -v node &>/dev/null; then
  install_file "$CONV_SRC" "$CONV_DEST"
  echo "  ${YELLOW}⚠ node not found — install Node 18+ then run: node .claude/tools/conventions.mjs${RESET}"
else
  install_file "$CONV_SRC" "$CONV_DEST"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would run: node .claude/tools/conventions.mjs${RESET}"
  else
    echo "  Scanning custom code..."
    if (cd "$TARGET_DIR" && node .claude/tools/conventions.mjs 2>&1 | sed 's/^/    /'); then
      CONV_FILE="$TARGET_DIR/.claude/conventions.md"
      if [[ -f "$CONV_FILE" ]]; then
        # Show the guidance section inline so the user sees actionable output.
        echo ""
        echo "  ${BOLD}Top guidance (excerpt):${RESET}"
        sed -n '/^## Guidance for code generation/,$p' "$CONV_FILE" \
          | tail -n +2 | head -8 | sed 's/^/    /'
        echo ""
        echo "  Full report: .claude/conventions.md"
      fi
    else
      echo "  ${YELLOW}⚠ Convention scan failed${RESET}" >&2
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7d — Knowledge scaffolds (ADRs, glossary, external systems, fixtures)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7d: Knowledge scaffolds${RESET}"

KNOWLEDGE_SRC="$TEMPLATE_DIR/assets/knowledge"

if [[ ! -d "$KNOWLEDGE_SRC" ]]; then
  echo "  ${YELLOW}⚠ Knowledge templates not found in ${KNOWLEDGE_SRC#"$TEMPLATE_DIR"/}${RESET}"
else
  install_file \
    "$KNOWLEDGE_SRC/glossary.md" \
    "$TARGET_DIR/.claude/glossary.md"

  install_file \
    "$KNOWLEDGE_SRC/external-systems.md" \
    "$TARGET_DIR/.claude/external-systems.md"

  install_file \
    "$KNOWLEDGE_SRC/test-fixtures.md" \
    "$TARGET_DIR/.claude/test-fixtures.md"

  install_file \
    "$KNOWLEDGE_SRC/decisions/README.md" \
    "$TARGET_DIR/.claude/decisions/README.md"

  install_file \
    "$KNOWLEDGE_SRC/decisions/0001-template.md" \
    "$TARGET_DIR/.claude/decisions/0001-template.md"

  echo "  ${GRAY}These files are scaffolds — fill them in as the project grows.${RESET}"
  echo "  ${GRAY}They are read by the coding agent when relevant.${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7e — Project map (content model, routes, services, roles, splits)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7e: Project map${RESET}"

MAP_SRC="$TEMPLATE_DIR/assets/tools/project-map.mjs"
MAP_DEST="$TARGET_DIR/.claude/tools/project-map.mjs"

if [[ "$SKIP_DETECT" == true ]]; then
  echo "  ${YELLOW}--skip-detect: skipping project map${RESET}"
elif [[ ! -f "$MAP_SRC" ]]; then
  echo "  ${YELLOW}⚠ project-map.mjs not found in template${RESET}"
elif ! command -v node &>/dev/null; then
  install_file "$MAP_SRC" "$MAP_DEST"
  echo "  ${YELLOW}⚠ node not found — install Node 18+ then run: node .claude/tools/project-map.mjs${RESET}"
else
  install_file "$MAP_SRC" "$MAP_DEST"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would run: node .claude/tools/project-map.mjs${RESET}"
  else
    echo "  Scanning Drupal config + custom module YAMLs..."
    if (cd "$TARGET_DIR" && node .claude/tools/project-map.mjs 2>&1 | sed 's/^/    /'); then
      echo "  Full report: .claude/project-map.md"
    else
      echo "  ${YELLOW}⚠ Project map scan failed${RESET}" >&2
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 7i — Live site-API index (.claude/site-api.json)
#
# High-fidelity ground truth from the RUNNING site (valid service IDs, real
# entity/bundle/field machine names, routes, permissions, modules) so the agent
# verifies identifiers before generating code. Requires a bootable site via
# Drush; when unavailable, project-map.md (Phase 7e) stays the static fallback.
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 7i: Site-API index${RESET}"

SITE_API_PHP_SRC="$TEMPLATE_DIR/assets/tools/site-api.php"
SITE_API_SH_SRC="$TEMPLATE_DIR/assets/tools/site-api.sh"
SITE_API_PHP_DEST="$TARGET_DIR/.claude/tools/site-api.php"
SITE_API_SH_DEST="$TARGET_DIR/.claude/tools/site-api.sh"

# Resolve a Drush runner the same way the lint hook resolves phpcs.
SITE_API_DRUSH=""
if command -v ddev &>/dev/null && [[ -f "$TARGET_DIR/.ddev/config.yaml" ]]; then
  SITE_API_DRUSH="ddev drush"
elif [[ -x "$TARGET_DIR/vendor/bin/drush" ]]; then
  SITE_API_DRUSH="$TARGET_DIR/vendor/bin/drush"
elif command -v drush &>/dev/null; then
  SITE_API_DRUSH="drush"
fi

if [[ "$SKIP_DETECT" == true ]]; then
  echo "  ${YELLOW}--skip-detect: skipping site-API index${RESET}"
elif [[ ! -f "$SITE_API_PHP_SRC" || ! -f "$SITE_API_SH_SRC" ]]; then
  echo "  ${YELLOW}⚠ site-api tools not found in template${RESET}"
elif [[ -z "$SITE_API_DRUSH" ]]; then
  # Still install the tools so the user can run them once the site is up.
  install_file "$SITE_API_PHP_SRC" "$SITE_API_PHP_DEST"
  install_file_executable "$SITE_API_SH_SRC" "$SITE_API_SH_DEST"
  warn "No Drush runner (ddev / vendor/bin/drush / global) — skipping site-api.json"
  echo "  ${GRAY}project-map.md remains the static fallback; run .claude/tools/site-api.sh once the site is up${RESET}"
  SITE_API_STATUS="skipped (no drush)"
else
  install_file "$SITE_API_PHP_SRC" "$SITE_API_PHP_DEST"
  install_file_executable "$SITE_API_SH_SRC" "$SITE_API_SH_DEST"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would run: .claude/tools/site-api.sh${RESET}"
    SITE_API_STATUS="dry-run"
  else
    echo "  Introspecting running site via Drush..."
    if (cd "$TARGET_DIR" && ./.claude/tools/site-api.sh 2>&1 | sed 's/^/    /'); then
      SITE_API_STATUS="generated"
    else
      warn "Site introspection failed (site not bootstrapped?) — falling back to project-map.md"
      SITE_API_STATUS="failed (site down)"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 8 — Summary
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
echo "  ${BOLD}Version-aware artifacts${RESET}"
echo "    Version guide   : ${VERSION_GUIDE_STATUS}"
echo "    Examples checkout: ${EXAMPLES_STATUS}"
echo "    gitignore block : ${GITIGNORE_STATUS}"
echo "    Site-API index  : ${SITE_API_STATUS}"
echo ""
echo "══════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Notice: AI_CONTEXT.md files already tracked by git
#
# These should be gitignored (see Phase 7h). We never run git mutations
# automatically — print the exact command the user can run themselves.
# ---------------------------------------------------------------------------
if command -v git &>/dev/null && [[ -d "$TARGET_DIR/.git" ]]; then
  TRACKED_AI_CONTEXT="$( (cd "$TARGET_DIR" && git ls-files web/modules/custom/*/AI_CONTEXT.md 2>/dev/null) || true )"
  if [[ -n "$TRACKED_AI_CONTEXT" ]]; then
    echo "  ${YELLOW}⚠ AI_CONTEXT.md files are already tracked by git${RESET}"
    echo "    These are intended to be gitignored (the managed block in"
    echo "    .gitignore was just added/updated). Untrack them with:"
    echo ""
    # Build a single-line command listing all files.
    UNTRACK_ARGS=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      UNTRACK_ARGS+=" $f"
    done <<< "$TRACKED_AI_CONTEXT"
    echo "      git rm --cached${UNTRACK_ARGS}"
    echo ""
    echo "    (drupal-agentic-workflow does not run git mutations for you.)"
    echo ""
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 9 — Interactive follow-ups (optionally launch claude per task)
# ═══════════════════════════════════════════════════════════════════════════

# Prompts the agent should run. Kept as parallel arrays so they're easy to maintain.
FOLLOWUP_LABELS=(
  "Fill in CLAUDE.md project details"
  "Verify the auto-populated 'Custom Modules' descriptions in CLAUDE.md"
  "Populate the 'Installed Contributed Modules/Themes' section in CLAUDE.md"
  "Review per-module AI_CONTEXT.md files"
)
FOLLOWUP_PROMPTS=(
  "Review CLAUDE.md in this project and fill in any TODO or placeholder sections (project overview, architecture description, environment notes). Use .claude/stack.json, .claude/project-map.md, and .claude/conventions.md as ground truth. Do not modify the managed block between the drupal-agentic-workflow:start and drupal-agentic-workflow:end markers — only edit content outside of it."
  "Review the 'Custom Modules' section in CLAUDE.md. For each listed module, verify the one-line description matches what the module actually does. Cross-reference with .claude/project-map.md (services, routes per module) and each module's AI_CONTEXT.md if present. Update descriptions where they are missing, vague, or misleading."
  "Populate the 'Installed Contributed Modules/Themes' section in CLAUDE.md from composer.json. For each drupal/* dependency (excluding core and core-* packages), list the package name with version constraint and a one-line summary of its purpose. Group by category if there are many (admin, content, search, performance, etc.). Skip drupal/core, drupal/core-*, and dev-only packages."
  "For each web/modules/custom/*/AI_CONTEXT.md file, review the auto-generated content against the actual module code. The 'Key Files', 'Hooks', 'Routes', and 'Services' tables were extracted automatically — keep them intact. Append a 'Domain notes' section to each where you can capture: business logic the agent should know, integration touchpoints, gotchas, and any non-obvious behavior."
)

# Always write the prompts to a file the user can rerun manually later.
# (Skip the actual write on dry-run since .claude/ may not exist yet.)
FOLLOWUPS_FILE="$TARGET_DIR/.claude/followups.md"
if [[ "$DRY_RUN" != true ]]; then
  mkdir -p "$TARGET_DIR/.claude"
fi
[[ "$DRY_RUN" == true ]] && FOLLOWUPS_FILE="/dev/null"
{
  echo "# Follow-up prompts for claude"
  echo ""
  echo "> Generated by drupal-agentic-workflow setup. These are the recommended"
  echo "> next-step prompts to refine your project's agent context. Run them with"
  echo "> \`claude \"<prompt>\"\` from the project root, or re-run setup.sh to be"
  echo "> offered interactively again."
  echo ""
  for i in "${!FOLLOWUP_LABELS[@]}"; do
    n=$((i + 1))
    echo "## $n. ${FOLLOWUP_LABELS[$i]}"
    echo ""
    echo '```'
    echo "${FOLLOWUP_PROMPTS[$i]}"
    echo '```'
    echo ""
  done
} > "$FOLLOWUPS_FILE"

if [[ "$SKIP_FOLLOWUPS" == true ]]; then
  echo "  ${YELLOW}--skip-followups: not offering interactive next steps${RESET}"
  echo "  Prompts saved to .claude/followups.md — run them manually with \`claude \"<prompt>\"\`."
elif [[ "$DRY_RUN" == true ]]; then
  echo "  ${GRAY}(dry-run) Would offer 4 follow-up prompts via claude CLI${RESET}"
  echo "  Prompts saved to .claude/followups.md"
elif ! command -v claude &>/dev/null; then
  echo "  ${GRAY}claude CLI not found on PATH — skipping interactive follow-ups${RESET}"
  echo "  Prompts saved to .claude/followups.md — run them when claude is installed."
elif [[ ! -t 0 ]]; then
  echo "  ${GRAY}Non-interactive shell — skipping follow-ups${RESET}"
  echo "  Prompts saved to .claude/followups.md"
else
  echo "  ${BOLD}Optional follow-ups${RESET} — refine the project's agent context."
  echo "  For each task, you can launch claude with a prepared prompt."
  echo "  All prompts are saved to .claude/followups.md for later use."
  echo ""

  for i in "${!FOLLOWUP_LABELS[@]}"; do
    n=$((i + 1))
    echo "  ${BOLD}$n. ${FOLLOWUP_LABELS[$i]}${RESET}"
    echo -n "     Launch claude for this? [y/N/q to quit] "
    read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
    case "$REPLY" in
      [Yy]*)
        echo "  ${GRAY}Launching claude in $TARGET_DIR...${RESET}"
        (cd "$TARGET_DIR" && claude "${FOLLOWUP_PROMPTS[$i]}") || \
          echo "  ${YELLOW}⚠ claude exited non-zero${RESET}"
        ;;
      [Qq]*)
        echo "  ${GRAY}Quitting follow-ups (remaining prompts are in .claude/followups.md)${RESET}"
        break
        ;;
      *)
        echo "  ${GRAY}Skipped.${RESET}"
        ;;
    esac
    echo ""
  done
fi

echo ""
echo "══════════════════════════════════════════════"
echo ""
