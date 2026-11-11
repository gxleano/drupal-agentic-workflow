#!/usr/bin/env bash
#
# setup.sh — Install drupal-agentic-workflow into a target Drupal project.
#
# Usage: bin/setup.sh [TARGET_DIR] [OPTIONS]
#   TARGET_DIR    Path to a Drupal project root (default: current directory)
#   --force       Skip Drupal project detection; overwrite customized files
#   --dry-run     Show what would be done without making changes
#   --skip-tools  Skip code quality tools detection/installation
#   --help        Show this help message
#
# Phases:
#   0. Validate target is a Drupal project (composer.json with drupal/core)
#   1. Check and install code quality tools (phpcs, phpstan); write a
#      phpstan.neon that actually loads phpstan-drupal
#   2. Copy .claude/ (hooks + lib, settings, site-api tool)
#   3. Write a short AGENTS.md template and a CLAUDE.md that imports it
#      (only when missing — never touches existing instruction files)
#   4. Add generated files to .gitignore
#   5. Print summary and next steps
#
# The workflow installs checks that run (hooks) and a tool that reads the live
# site on demand. It deliberately does not generate descriptive context files:
# they go stale as soon as the code changes, and agents trust them anyway.
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
  --force       Skip Drupal project detection; overwrite customized files
  --dry-run     Show what would be done without making changes
  --skip-tools  Skip code quality tools detection/installation
  --help        Show this help message

Phases:
  0. Validate target is a Drupal project (composer.json with drupal/core)
  1. Check and install code quality tools; write a working phpstan.neon
  2. Copy .claude/ (hooks + lib, settings, site-api tool)
  3. Write AGENTS.md template + CLAUDE.md import (only when missing)
  4. Add generated files to .gitignore
  5. Print summary and next steps
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

warn() {
  echo "  ${YELLOW}⚠${RESET} $*" >&2
}

# ---------------------------------------------------------------------------
# Helper: install_file SOURCE DEST [executable]
#
# Implements the idempotency rules described at the top of this file.
# ---------------------------------------------------------------------------
install_file() {
  local src="$1"
  local dest="$2"
  local executable="${3:-}"
  local relative_dest="${dest#"$TARGET_DIR"/}"

  if [[ -f "$dest" ]] && diff -q "$src" "$dest" &>/dev/null; then
    log_up_to_date "$relative_dest"
    UP_TO_DATE=$((UP_TO_DATE + 1))
    return
  fi

  if [[ -f "$dest" && "$FORCE" != true ]]; then
    log_skipped "$relative_dest"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  local note=""
  [[ -f "$dest" ]] && note=" (forced)"
  if [[ "$DRY_RUN" == true ]]; then
    log_installed "$relative_dest$note (dry-run)"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    [[ "$executable" == executable ]] && chmod +x "$dest"
    log_installed "$relative_dest$note"
  fi
  INSTALLED=$((INSTALLED + 1))
}

# ---------------------------------------------------------------------------
# Helper: merge_settings SOURCE DEST
#
# A project's settings.json often holds other hooks or permissions already,
# so it is merged instead of skipped: each hook command of SOURCE that DEST
# lacks is added under the same event. Nothing in DEST is changed or removed.
# --force still overwrites it, like any other file.
# ---------------------------------------------------------------------------
merge_settings() {
  local src="$1" dest="$2" merged
  local relative_dest="${dest#"$TARGET_DIR"/}"

  if [[ ! -f "$dest" || "$FORCE" == true ]] || ! command -v jq &>/dev/null; then
    install_file "$src" "$dest"
    return
  fi

  if ! merged=$(jq -s '
      .[0] as $dest | .[1] as $src
      | [$dest | .. | objects | select(has("command")) | .command] as $have
      | reduce ($src.hooks // {} | to_entries[]) as $event ($dest;
          reduce $event.value[] as $group (.;
            [$group.hooks[] | select(.command as $c | any($have[]; . == $c) | not)] as $new
            | if ($new | length) == 0 then .
              else .hooks[$event.key] = ((.hooks[$event.key] // []) + [$group + {hooks: $new}])
              end))
    ' "$dest" "$src" 2>/dev/null); then
    warn "$relative_dest is not valid JSON — left untouched; add the hooks from $src by hand."
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if [[ "$(jq -S . "$dest")" == "$(jq -S . <<< "$merged")" ]]; then
    log_up_to_date "$relative_dest"
    UP_TO_DATE=$((UP_TO_DATE + 1))
  elif [[ "$DRY_RUN" == true ]]; then
    log_installed "$relative_dest (hooks merged, dry-run)"
    INSTALLED=$((INSTALLED + 1))
  else
    printf '%s\n' "$merged" > "$dest"
    log_installed "$relative_dest (hooks merged)"
    INSTALLED=$((INSTALLED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Helper: composer_has PACKAGE — true when composer.json requires PACKAGE in
# require or require-dev.
# ---------------------------------------------------------------------------
composer_has() {
  jq -e --arg p "$1" '(.require[$p] // .["require-dev"][$p]) != null' \
    "$TARGET_DIR/composer.json" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Helper: allow_composer_plugin PLUGIN — Composer 2.2+ refuses to run a plugin
# that is not allow-listed, which makes every later `composer require` fail.
# ---------------------------------------------------------------------------
allow_composer_plugin() {
  local plugin="$1"
  if jq -e --arg p "$plugin" \
      '(.config["allow-plugins"] == true) or (.config["allow-plugins"][$p] == true)' \
      "$TARGET_DIR/composer.json" >/dev/null 2>&1; then
    return
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would allow Composer plugin: $plugin${RESET}"
    return
  fi
  echo "  ${YELLOW}⚠ Composer plugin not allow-listed: $plugin${RESET}"
  echo -n "  Allow it? [Y/n] "
  read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
  if [[ "$REPLY" =~ ^[Yy]?$ ]]; then
    if "${COMPOSER_RUN[@]}" config --no-plugins "allow-plugins.$plugin" true 2>&1 | sed 's/^/    /'; then
      echo "  ${GREEN}✓ allowed $plugin${RESET}"
    else
      warn "Failed — set manually: $COMPOSER_HINT config allow-plugins.$plugin true"
    fi
  else
    echo "  ${GRAY}Skipped — composer installs that need it will fail.${RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Helper: offer_require LABEL DEFAULT PACKAGE... — prompt, then
# `composer require --dev`. DEFAULT is Y or N.
# ---------------------------------------------------------------------------
offer_require() {
  local label="$1" default="$2"
  shift 2
  echo ""
  echo "  Missing $label packages: $*"
  if [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would offer: $COMPOSER_HINT require --dev $*${RESET}"
    return
  fi
  local prompt="[Y/n]" pattern='^[Yy]?$'
  if [[ "$default" == N ]]; then
    prompt="[y/N]"
    pattern='^[Yy]$'
  fi
  echo -n "  Install via $COMPOSER_HINT require --dev? $prompt "
  read -r REPLY < /dev/tty 2>/dev/null || REPLY="n"
  if [[ "$REPLY" =~ $pattern ]]; then
    if "${COMPOSER_RUN[@]}" require --dev "$@" 2>&1 | sed 's/^/    /'; then
      echo "  ${GREEN}✓ installed${RESET}"
    else
      warn "Installation failed — install manually: $COMPOSER_HINT require --dev $*"
    fi
  else
    echo "  ${GRAY}Skipped. Install manually: $COMPOSER_HINT require --dev $*${RESET}"
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

if ! command -v jq &>/dev/null; then
  warn "jq not found — the hooks need it. Install: brew install jq (macOS) or apt-get install jq"
fi

# Web root from the scaffold config (drupal/recommended-project uses web/).
WEB_ROOT="web"
if [[ -f "$TARGET_DIR/composer.json" ]] && command -v jq &>/dev/null; then
  WEB_ROOT=$(jq -r '.extra["drupal-scaffold"].locations["web-root"] // "web/"' \
    "$TARGET_DIR/composer.json" 2>/dev/null || echo "web/")
  WEB_ROOT="${WEB_ROOT%/}"
  WEB_ROOT="${WEB_ROOT#./}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 1 — Code Quality Tools
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 1: Code Quality Tools${RESET}"

if [[ "$SKIP_TOOLS" == true ]]; then
  echo "  ${YELLOW}--skip-tools: skipping code quality tools check${RESET}"
elif [[ ! -f "$TARGET_DIR/composer.json" ]]; then
  warn "No composer.json — skipping tool checks"
else
  # Prefer DDEV, else fall back to host binaries so non-DDEV projects work.
  if command -v ddev &>/dev/null && [[ -f "$TARGET_DIR/.ddev/config.yaml" ]]; then
    COMPOSER_RUN=(ddev composer)
  else
    COMPOSER_RUN=(composer "--working-dir=$TARGET_DIR")
  fi
  COMPOSER_HINT="${COMPOSER_RUN[*]}"

  # drupal/coder pulls in the phpcs installer plugin; phpstan's extension
  # installer is a plugin too. Both must be allow-listed before any require.
  allow_composer_plugin "dealerdirect/phpcodesniffer-composer-installer"
  allow_composer_plugin "phpstan/extension-installer"

  MISSING_REQUIRED=()
  MISSING_RECOMMENDED=()
  if composer_has "drupal/coder"; then
    echo "  ${GREEN}✓ drupal/coder${RESET}"
  else
    MISSING_REQUIRED+=("drupal/coder")
    echo "  ${YELLOW}✗ drupal/coder${RESET} — required for phpcs Drupal/DrupalPractice standards"
  fi
  # The extension installer is what loads phpstan-drupal and the deprecation
  # rules; without it the "drupal:" parameters in phpstan.neon are rejected.
  for pkg in phpstan/phpstan mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules phpstan/extension-installer; do
    if composer_has "$pkg"; then
      echo "  ${GREEN}✓ $pkg${RESET}"
    else
      MISSING_RECOMMENDED+=("$pkg")
      echo "  ${GRAY}○ $pkg${RESET} (recommended)"
    fi
  done

  if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
    offer_require "required" Y "${MISSING_REQUIRED[@]}"
  fi
  if [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
    offer_require "recommended" N "${MISSING_RECOMMENDED[@]}"
  fi
fi

# --- phpstan.neon -----------------------------------------------------------
# Without phpstan/extension-installer nothing loads phpstan-drupal, so the
# extension files are listed under includes: explicitly.
PHPSTAN_NEON="$TARGET_DIR/phpstan.neon"
if [[ -f "$PHPSTAN_NEON" || -f "$TARGET_DIR/phpstan.neon.dist" ]]; then
  echo ""
  echo "  ${GREEN}✓ phpstan config exists${RESET}"
  EXISTING_NEON="$PHPSTAN_NEON"
  [[ -f "$EXISTING_NEON" ]] || EXISTING_NEON="$TARGET_DIR/phpstan.neon.dist"
  if grep -qE '^[[:space:]]+drupal:' "$EXISTING_NEON" \
      && ! grep -q 'phpstan-drupal' "$EXISTING_NEON" \
      && ! composer_has "phpstan/extension-installer"; then
    warn "${EXISTING_NEON##*/} sets drupal: parameters but nothing loads phpstan-drupal."
    echo "    PHPStan will fail with \"Unexpected item 'parameters › drupal'\". Fix with either:"
    echo "      composer require --dev phpstan/extension-installer"
    echo "    or add to ${EXISTING_NEON##*/}:"
    echo "      includes:"
    echo "        - vendor/mglaman/phpstan-drupal/extension.neon"
    echo "        - vendor/mglaman/phpstan-drupal/rules.neon"
  fi
else
  NEON_INCLUDES=()
  if ! composer_has "phpstan/extension-installer"; then
    if composer_has "mglaman/phpstan-drupal"; then
      NEON_INCLUDES+=("vendor/mglaman/phpstan-drupal/extension.neon" "vendor/mglaman/phpstan-drupal/rules.neon")
    fi
    if composer_has "phpstan/phpstan-deprecation-rules"; then
      NEON_INCLUDES+=("vendor/phpstan/phpstan-deprecation-rules/rules.neon")
    fi
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log_installed "phpstan.neon (dry-run)"
  else
    {
      if [[ ${#NEON_INCLUDES[@]} -gt 0 ]]; then
        echo "includes:"
        for inc in "${NEON_INCLUDES[@]}"; do
          echo "  - $inc"
        done
      fi
      echo "parameters:"
      echo "  level: 2"
      echo "  paths:"
      echo "    - $WEB_ROOT/modules/custom"
      if composer_has "mglaman/phpstan-drupal"; then
        echo "  drupal:"
        echo "    drupal_root: $WEB_ROOT"
      fi
    } > "$PHPSTAN_NEON"
    log_installed "phpstan.neon"
  fi
  INSTALLED=$((INSTALLED + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 2 — Copy .claude/ (hooks + lib, settings, site-api tool)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 2: Installing .claude/ directory${RESET}"

merge_settings "$TEMPLATE_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"

for hook in pre-bash-guard.sh post-generation-lint.sh post-session-phpstan.sh; do
  install_file "$TEMPLATE_DIR/.claude/hooks/$hook" "$TARGET_DIR/.claude/hooks/$hook" executable
done
# Both PHP hooks source this library; without it they exit 1 on every run,
# which Claude Code treats as a non-blocking error and ignores.
install_file "$TEMPLATE_DIR/.claude/hooks/lib/php-tools.sh" "$TARGET_DIR/.claude/hooks/lib/php-tools.sh"
install_file "$TEMPLATE_DIR/.claude/hooks/README.md" "$TARGET_DIR/.claude/hooks/README.md"


# site-api reads the running site on demand. It is installed, not run: a
# snapshot taken at setup time is stale after the next module or field change.
install_file "$TEMPLATE_DIR/assets/tools/site-api.php" "$TARGET_DIR/.claude/tools/site-api.php"
install_file "$TEMPLATE_DIR/assets/tools/site-api.sh" "$TARGET_DIR/.claude/tools/site-api.sh" executable

# ═══════════════════════════════════════════════════════════════════════════
# Phase 3 — AGENTS.md + CLAUDE.md (only when missing)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 3: Instruction files${RESET}"

AGENTS_DEST="$TARGET_DIR/AGENTS.md"
if [[ -f "$AGENTS_DEST" ]]; then
  echo "  ${GRAY}✓ AGENTS.md exists — left untouched${RESET}"
  if grep -q 'drupal-agentic-workflow:start' "$AGENTS_DEST"; then
    warn "AGENTS.md still has the old managed block (drupal-agentic-workflow:start/end)."
    echo "    It is no longer updated. Trim it by hand using AGENTS-TEMPLATE.md as a guide."
  fi
else
  install_file "$TEMPLATE_DIR/AGENTS-TEMPLATE.md" "$AGENTS_DEST"
fi

CLAUDE_DEST="$TARGET_DIR/CLAUDE.md"
if [[ -f "$CLAUDE_DEST" ]]; then
  if grep -q '^@AGENTS.md' "$CLAUDE_DEST"; then
    echo "  ${GRAY}✓ CLAUDE.md imports AGENTS.md${RESET}"
  else
    warn "CLAUDE.md exists but does not import AGENTS.md — add a line: @AGENTS.md"
  fi
elif [[ "$DRY_RUN" == true ]]; then
  log_installed "CLAUDE.md (dry-run)"
  INSTALLED=$((INSTALLED + 1))
else
  printf '@AGENTS.md\n' > "$CLAUDE_DEST"
  log_installed "CLAUDE.md"
  INSTALLED=$((INSTALLED + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 4 — .gitignore
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Phase 4: .gitignore${RESET}"

GITIGNORE="$TARGET_DIR/.gitignore"
for entry in ".claude/site-api.json" ".claude/settings.local.json"; do
  if [[ -f "$GITIGNORE" ]] && grep -qxF "$entry" "$GITIGNORE"; then
    echo "  ${GRAY}✓ $entry already ignored${RESET}"
  elif [[ "$DRY_RUN" == true ]]; then
    echo "  ${GRAY}(dry-run) Would add $entry${RESET}"
  else
    printf '%s\n' "$entry" >> "$GITIGNORE"
    echo "  ${GREEN}✚ ignored:${RESET} $entry"
  fi
done

# ═══════════════════════════════════════════════════════════════════════════
# Phase 5 — Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "${BOLD}Summary${RESET}"
echo "  installed: $INSTALLED   up to date: $UP_TO_DATE   skipped (customized): $SKIPPED"
if [[ "$SKIPPED" -gt 0 ]]; then
  echo "  ${GRAY}Re-run with --force to overwrite customized files.${RESET}"
fi
echo ""
echo "${BOLD}Next steps${RESET}"
echo "  1. Fill in AGENTS.md. Run every command before you write it down."
echo "  2. Check the hooks fire: edit a PHP file in a session and watch for the lint output."
echo "  3. When an agent needs real service/field/route names: .claude/tools/site-api.sh"
