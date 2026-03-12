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
#   7. Print summary with counts and next steps
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
SKIP_AI_CONTEXT=false

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
  --help             Show this help message

Phases:
  0. Validate target is a Drupal project (composer.json with drupal/core)
  1. Check and install code quality tools (phpcs, phpstan)
  2. Copy .claude/ directory (skills, hooks, settings)
  3. Append Drupal rules to CLAUDE.md (or create from template)
  4. Install .prettierrc.json (if missing)
  5. (Optional) Analyze custom modules and generate AI_CONTEXT.md files
  6. Update CLAUDE.md Custom Modules section with discovered modules
  7. Print summary with counts and next steps
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
  local key_files=""
  local has_module_file=false
  local has_routing=false
  local has_services=false
  local has_permissions=false
  local has_libraries=false
  local has_install=false
  local has_config_install=false
  local has_config_schema=false
  local has_templates=false
  local has_migrations=false

  [[ -f "$module_dir/${machine_name}.module" ]] && has_module_file=true
  [[ -f "$module_dir/${machine_name}.routing.yml" ]] && has_routing=true
  [[ -f "$module_dir/${machine_name}.services.yml" ]] && has_services=true
  [[ -f "$module_dir/${machine_name}.permissions.yml" ]] && has_permissions=true
  [[ -f "$module_dir/${machine_name}.libraries.yml" ]] && has_libraries=true
  [[ -f "$module_dir/${machine_name}.install" ]] && has_install=true
  [[ -d "$module_dir/config/install" ]] && has_config_install=true
  [[ -d "$module_dir/config/schema" ]] && has_config_schema=true
  [[ -d "$module_dir/templates" ]] && has_templates=true
  [[ -d "$module_dir/migrations" || -d "$module_dir/config/install" ]] && \
    ls "$module_dir"/config/install/migrate.migration.* 2>/dev/null | grep -q . && has_migrations=true

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
      awk -v listing="$MODULE_LISTING" '
        /<!-- List your custom modules here\./ {
          # Skip until closing -->
          while ($0 !~ /-->/) { if ((getline) <= 0) break }
          printf "%s", listing
          next
        }
        { print }
      ' "$TARGET_DIR/CLAUDE.md" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$TARGET_DIR/CLAUDE.md"
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
# Phase 7 — Summary
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
echo "  2. Review the auto-populated \"Custom Modules\" section in CLAUDE.md"
echo "  3. List installed contrib modules in the \"Contributed Modules\" section"
echo "  4. Review generated AI_CONTEXT.md files and add any missing context"
echo ""
echo "══════════════════════════════════════════════"
echo ""
