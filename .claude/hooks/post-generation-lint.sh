#!/usr/bin/env bash
#
# Post-generation hook for Claude Code.
# Detects changed file types and runs the appropriate linters.
# Exit code 2 = blocking error (fed back to Claude as feedback).
#
set -euo pipefail

# Claude Code ignores any exit code but 0 and 2, so a crash would pass in
# silence and the file would look checked. Any other exit (set -e, a missing
# command) becomes exit 2 with a note, so it reaches Claude. An EXIT trap, not
# ERR: it is not inherited by $(…), where tools exit 1 on purpose.
on_exit() {
  local rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    echo "post-generation-lint.sh failed unexpectedly (exit $rc); the file was not checked." >&2
    exit 2
  fi
}
trap on_exit EXIT

# ── Read hook input from stdin ───────────────────────────────────────────────
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ── Resolve project root ────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Shared PHP tool resolution (DDEV → vendor/bin → $PATH → global Composer).
HOOK_LIB="$(dirname "$0")/lib/php-tools.sh"
if [[ ! -f "$HOOK_LIB" ]]; then
  echo "post-generation-lint.sh: $HOOK_LIB is missing, so no file is linted." >&2
  echo "Reinstall the hooks (vendor/bin/daw update) or ask the user to." >&2
  exit 2
fi
# shellcheck source=lib/php-tools.sh
source "$HOOK_LIB"

# ── Helpers ──────────────────────────────────────────────────────────────────
ERRORS=0
TOOLS_RUN=()
# A note for Claude that is not an error (sent as context with exit 0).
NOTE=""

log_header() {
  echo "──────────────────────────────────────────────" >&2
  echo "  Post-Generation Lint Hook" >&2
  echo "──────────────────────────────────────────────" >&2
}

log_file() {
  echo "" >&2
  echo "  File detected : $1" >&2
  echo "  File type     : $2" >&2
}

log_tool_start() {
  echo "" >&2
  echo "  Running       : $1" >&2
}

log_tool_result() {
  local tool="$1"
  local exit_code="$2"
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  Result        : $tool PASSED" >&2
  else
    echo "  Result        : $tool FAILED (exit $exit_code)" >&2
  fi
}

log_summary() {
  echo "" >&2
  echo "──────────────────────────────────────────────" >&2
  echo "  Tools executed: ${TOOLS_RUN[*]:-none}" >&2
  if [[ "$ERRORS" -gt 0 ]]; then
    echo "  Status        : FAILED ($ERRORS error(s))" >&2
  else
    echo "  Status        : PASSED" >&2
  fi
  echo "──────────────────────────────────────────────" >&2
}

# ── Determine file type ─────────────────────────────────────────────────────
EXT="${FILE_PATH##*.}"
BASENAME=$(basename "$FILE_PATH")

is_backend() {
  case "$EXT" in
    php|module|theme|install|inc|profile|test) return 0 ;;
  esac
  return 1
}

is_javascript() {
  case "$EXT" in
    js|jsx|mjs|cjs|ts|tsx) return 0 ;;
  esac
  return 1
}

is_stylesheet() {
  case "$EXT" in
    css|scss|sass|less) return 0 ;;
  esac
  return 1
}

is_twig() {
  case "$BASENAME" in
    *.html.twig|*.twig) return 0 ;;
  esac
  return 1
}

# Drupal-managed YAML must NOT be reformatted by prettier. Drupal's config
# exporter uses the Symfony YAML dumper with its own style and quoting, so
# prettier produces a different-but-valid file that `drush cex` re-normalizes —
# causing endless diff churn — and quoting changes (e.g. version: '1.0') can be
# semantically significant. Covers config exports plus module/theme definition
# and plugin YAML shipped in code.
is_drupal_yaml() {
  case "$EXT" in
    yml|yaml) ;;
    *) return 1 ;;
  esac
  # Anything under a config/ directory (config/sync, config/install, config/schema, …).
  case "$FILE_PATH" in
    */config/*) return 0 ;;
  esac
  case "$BASENAME" in
    *.info.yml|*.routing.yml|*.services.yml|*.libraries.yml|\
    *.permissions.yml|*.links.menu.yml|*.links.task.yml|*.links.action.yml|\
    *.links.contextual.yml|*.menu.links.*.yml|*.breakpoints.yml|\
    *.schema.yml|*.settings.yml)
      return 0 ;;
  esac
  return 1
}

is_prettier_target() {
  is_javascript && return 0
  is_stylesheet && return 0
  is_twig && return 0
  is_drupal_yaml && return 1
  case "$EXT" in
    yaml|yml|json) return 0 ;;
  esac
  return 1
}

# A file inside a git submodule belongs to an upstream project with its own
# standards and CI. It is still checked, against the submodule's own ruleset,
# but never auto-fixed: that would put formatting changes nobody asked for
# into someone else's repository. Sets SUBMODULE to the submodule's path.
SUBMODULE=""
in_submodule() {
  [[ -f "$PROJECT_DIR/.gitmodules" ]] || return 1
  local rel="${FILE_PATH#"$PROJECT_DIR"/}" path
  while IFS= read -r path; do
    if [[ -n "$path" && "$rel" == "$path"/* ]]; then
      SUBMODULE="$path"
      return 0
    fi
  done < <(git config -f "$PROJECT_DIR/.gitmodules" --get-regexp '\.path$' 2>/dev/null | awk '{print $2}')
  return 1
}

# Finds the nearest config file named in $@ from the edited file's directory
# up to the project root, so a tool only runs where it has been set up.
find_config() {
  local dir
  dir="$(dirname "$FILE_PATH")"
  while :; do
    local name
    for name in "$@"; do
      if [[ -f "$dir/$name" ]]; then
        echo "$dir/$name"
        return 0
      fi
    done
    [[ "$dir" == "$PROJECT_DIR" || "$dir" == "/" || "$dir" == "." ]] && return 1
    dir="$(dirname "$dir")"
  done
}

# A linter that cannot load its config says nothing about the file: e.g.
# ESLint 9+ ignores the .eslintrc.json Drupal core ships. Reported as a setup
# problem, not sent back as a code error.
is_js_setup_failure() {
  grep -qiE "couldn't find (an eslint\.config|a configuration)|Oops! Something went wrong|No configuration provided|Cannot find module" <<< "$1"
}

# A local or global install only: plain `npx` would download the package
# when it is missing, which is slow and can hang on a prompt.
npx_tool() {
  npx --no-install "$@"
}

# Skip files outside the project or in vendor/contrib/core directories.
is_lintable() {
  case "$FILE_PATH" in
    */vendor/*|*/node_modules/*|*/web/core/*|*/web/modules/contrib/*|*/web/themes/contrib/*|*/web/profiles/*)
      return 1 ;;
  esac
  in_submodule || true
  # File must exist.
  [[ -f "$FILE_PATH" ]]
}

# ── Early exit for non-lintable files ────────────────────────────────────────
if ! is_lintable; then
  exit 0
fi

# Only proceed for file types we care about.
if ! is_backend && ! is_javascript && ! is_stylesheet && ! is_prettier_target; then
  exit 0
fi

log_header

# ── Backend: PHP / Drupal ────────────────────────────────────────────────────
if is_backend; then
  log_file "$FILE_PATH" "backend (PHP/Drupal)"

  # Make the path relative to the project root (used as the target so both the
  # ddev and vendor/bin runners resolve it identically from $PROJECT_DIR).
  REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

  # --- Resolve the phpcs/phpcbf runner ---------------------------------------
  # Resolution order (see lib/php-tools.sh): ddev (matches the project's
  # containerised toolchain and CI) → the repo's own vendor/bin → a phpcs on
  # $PATH → a global Composer install. The $PATH / global fallbacks let the
  # hook lint a standalone contrib module repo that has no Drupal/DDEV.
  PHPCS_AVAILABLE=true
  PHPCS_RUNNER=""; PHPCS_BIN=""
  PHPCBF_AVAILABLE=false
  PHPCBF_RUNNER=""; PHPCBF_BIN=""
  PHPCBF_FIXED=false

  if php_resolve_tool "$PROJECT_DIR" phpcs; then
    PHPCS_RUNNER="$PHP_TOOL_RUNNER"; PHPCS_BIN="$PHP_TOOL_BIN"
    echo "  phpcs runner  : $PHP_TOOL_SOURCE" >&2
  else
    PHPCS_AVAILABLE=false
    echo "  Skipping phpcbf/phpcs: no ddev project and no local phpcs found" >&2
    echo "  (looked in vendor/bin, \$PATH and the global Composer bin dir)." >&2
    echo "  Install Coder so the hook can lint:" >&2
    echo "    composer require --dev drupal/coder" >&2
  fi

  # phpcbf (auto-fix) is resolved independently — it lives alongside phpcs in
  # every install, but we degrade gracefully to phpcs-only if it's missing.
  if php_resolve_tool "$PROJECT_DIR" phpcbf; then
    PHPCBF_RUNNER="$PHP_TOOL_RUNNER"; PHPCBF_BIN="$PHP_TOOL_BIN"
    PHPCBF_AVAILABLE=true
  fi

  # --- Resolve the coding standard -------------------------------------------
  # Prefer the project's own ruleset so the hook agrees with CI exactly (it can
  # encode ignore patterns, PHPCompatibility testVersion, extra sniffs, etc.).
  # A ruleset file already defines its extensions, so only pass --extensions
  # for the bundled Drupal,DrupalPractice fallback.
  CS_ARGS=()
  if [[ -n "$SUBMODULE" && -f "$PROJECT_DIR/$SUBMODULE/phpcs.xml" ]]; then
    CS_ARGS=(--standard="$SUBMODULE/phpcs.xml")
  elif [[ -n "$SUBMODULE" && -f "$PROJECT_DIR/$SUBMODULE/phpcs.xml.dist" ]]; then
    CS_ARGS=(--standard="$SUBMODULE/phpcs.xml.dist")
  elif [[ -n "$SUBMODULE" ]]; then
    CS_ARGS=("--standard=Drupal,DrupalPractice"
             "--extensions=php,module,inc,install,test,profile,theme")
  elif [[ -f "$PROJECT_DIR/phpcs.xml" ]]; then
    CS_ARGS=(--standard=phpcs.xml)
  elif [[ -f "$PROJECT_DIR/phpcs.xml.dist" ]]; then
    CS_ARGS=(--standard=phpcs.xml.dist)
  else
    CS_ARGS=("--standard=Drupal,DrupalPractice"
             "--extensions=php,module,inc,install,test,profile,theme")
  fi

  # Detect a broken Coder install (missing standard / missing binary) in tool
  # output so we report a setup problem instead of a phantom code problem.
  is_setup_failure() {
    grep -qiE 'coding standard .* is not installed|ERROR: the .* standard|command not found|executable file not found' <<< "$1"
  }

  # Upstream code is reported, not rewritten.
  [[ -n "$SUBMODULE" ]] && PHPCBF_AVAILABLE=false

  if [[ "$PHPCS_AVAILABLE" == true && "$PHPCBF_AVAILABLE" == true ]]; then
    # --- PHPCBF (auto-fix) ---
    log_tool_start "phpcbf"
    TOOLS_RUN+=("phpcbf")
    PHPCBF_OUTPUT=""
    PHPCBF_EXIT=0
    PHPCBF_OUTPUT=$(php_exec_tool "$PROJECT_DIR" "$PHPCBF_RUNNER" "$PHPCBF_BIN" "${CS_ARGS[@]}" "$REL_PATH" 2>&1) || PHPCBF_EXIT=$?

    if [[ "$PHPCBF_EXIT" -eq 127 ]]; then
      # The resolved binary isn't actually runnable here — e.g. a global phpcbf
      # shim that expects a project-local install. Skip the whole CS step
      # non-blockingly (matches the "no tool found" behaviour), don't block.
      echo "  phpcbf resolved to a non-runnable binary ($PHPCBF_BIN) — skipping phpcs/phpcbf." >&2
      echo "  Install a working CodeSniffer for this repo:" >&2
      echo "    composer require --dev drupal/coder" >&2
      PHPCS_AVAILABLE=false
    elif is_setup_failure "$PHPCBF_OUTPUT"; then
      echo "  phpcbf could not run — Coder standards not installed correctly:" >&2
      echo "$PHPCBF_OUTPUT" >&2
      echo "  Fix: composer require --dev drupal/coder && \\" >&2
      echo "    vendor/bin/phpcs --config-set installed_paths vendor/drupal/coder/coder_sniffer" >&2
      ERRORS=$((ERRORS + 1))
      PHPCS_AVAILABLE=false
    elif [[ "$PHPCBF_EXIT" -eq 1 ]]; then
      # phpcbf exit 1 = fixable violations were fixed on disk.
      echo "  phpcbf: auto-fixed coding standard violations on disk." >&2
      PHPCBF_FIXED=true
    fi
    log_tool_result "phpcbf" 0  # phpcbf is best-effort, not a blocker
  fi

  if [[ "$PHPCS_AVAILABLE" == true ]]; then
    # --- PHPCS (-s shows sniff codes so remaining violations are actionable) ---
    log_tool_start "phpcs"
    TOOLS_RUN+=("phpcs")
    PHPCS_OUTPUT=""
    PHPCS_EXIT=0
    PHPCS_OUTPUT=$(php_exec_tool "$PROJECT_DIR" "$PHPCS_RUNNER" "$PHPCS_BIN" -s "${CS_ARGS[@]}" "$REL_PATH" 2>&1) || PHPCS_EXIT=$?

    if [[ "$PHPCS_EXIT" -eq 127 ]] || is_setup_failure "$PHPCS_OUTPUT"; then
      # Resolved phpcs is not functional (non-runnable shim or broken Coder
      # standard). Report it as a setup problem and skip — don't block on a
      # phantom code error.
      echo "  phpcs could not run — the resolved binary is not functional:" >&2
      echo "$PHPCS_OUTPUT" >&2
      echo "  Install a working CodeSniffer for this repo:" >&2
      echo "    composer require --dev drupal/coder" >&2
    elif [[ "$PHPCS_EXIT" -ne 0 ]]; then
      echo "$PHPCS_OUTPUT" >&2
      # phpcbf rewrote the file on disk; Claude's in-context copy is now stale.
      # The violations above survived auto-fix (no fixer) and need manual edits.
      if [[ "$PHPCBF_FIXED" == true ]]; then
        echo "" >&2
        echo "  NOTE: phpcbf modified $REL_PATH on disk — re-read it before editing" >&2
        echo "  (your in-context copy is stale). The violations above have no" >&2
        echo "  auto-fixer; fix them by hand using the sniff codes shown." >&2
      fi
      ERRORS=$((ERRORS + 1))
    elif [[ "$PHPCBF_FIXED" == true ]]; then
      # phpcs is clean, but phpcbf rewrote the file. Nothing to fix, so it is
      # not an error: Claude gets a note as context and carries on.
      NOTE="phpcbf auto-fixed $REL_PATH on disk and phpcs now passes. Re-read the file before editing it again: your copy is from before the fix."
    fi
    log_tool_result "phpcs" "$PHPCS_EXIT"
  fi
fi

# ── Formatting: Prettier ──────────────────────────────────────────────────────
if is_prettier_target && [[ -z "$SUBMODULE" ]]; then
  if command -v npx &>/dev/null && npx_tool prettier --version &>/dev/null; then
    # Check if Twig plugin is available for Twig files.
    SKIP_PRETTIER=false
    if is_twig; then
      if ! npm ls prettier-plugin-twig-melody &>/dev/null 2>&1; then
        echo "  Skipping prettier for Twig: prettier-plugin-twig-melody not installed" >&2
        SKIP_PRETTIER=true
      fi
    fi

    if [[ "$SKIP_PRETTIER" == "false" ]]; then
      log_file "$FILE_PATH" "formatting (Prettier)"
      log_tool_start "prettier"
      TOOLS_RUN+=("prettier")
      PRETTIER_OUTPUT=""
      PRETTIER_EXIT=0
      PRETTIER_OUTPUT=$(npx_tool prettier --write "$FILE_PATH" 2>&1) || PRETTIER_EXIT=$?

      if [[ "$PRETTIER_EXIT" -ne 0 ]]; then
        echo "$PRETTIER_OUTPUT" >&2
        ERRORS=$((ERRORS + 1))
      fi
      log_tool_result "prettier" "$PRETTIER_EXIT"
    fi
  else
    echo "  Skipping prettier: not available" >&2
  fi
fi

# ── Frontend: JavaScript ─────────────────────────────────────────────────────
if is_javascript; then
  log_file "$FILE_PATH" "frontend (JavaScript/TypeScript)"

  # --- ESLint ---
  # Without a config ESLint fails on any file, which says nothing about it.
  if ! find_config eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
       .eslintrc.json .eslintrc.js .eslintrc.cjs .eslintrc.yml .eslintrc.yaml .eslintrc >/dev/null; then
    echo "  Skipping eslint: no ESLint config between the file and the project root" >&2
  elif command -v npx &>/dev/null; then
    log_tool_start "eslint"
    TOOLS_RUN+=("eslint")
    ESLINT_OUTPUT=""
    ESLINT_EXIT=0
    ESLINT_OUTPUT=$(npx_tool eslint --no-error-on-unmatched-pattern "$FILE_PATH" 2>&1) || ESLINT_EXIT=$?

    if [[ "$ESLINT_EXIT" -ne 0 ]] && is_js_setup_failure "$ESLINT_OUTPUT"; then
      echo "  eslint could not load its config here, so the file was not checked:" >&2
      echo "$ESLINT_OUTPUT" | head -n 5 >&2
    elif [[ "$ESLINT_EXIT" -ne 0 ]]; then
      echo "$ESLINT_OUTPUT" >&2
      ERRORS=$((ERRORS + 1))
    fi
    log_tool_result "eslint" "$ESLINT_EXIT"
  else
    echo "  Skipping eslint: npx not found" >&2
  fi
fi

# ── Frontend: CSS/SCSS ───────────────────────────────────────────────────────
if is_stylesheet; then
  log_file "$FILE_PATH" "frontend (CSS/SCSS)"

  # --- Stylelint ---
  if ! find_config .stylelintrc .stylelintrc.json .stylelintrc.js .stylelintrc.cjs .stylelintrc.yml \
       .stylelintrc.yaml stylelint.config.js stylelint.config.mjs stylelint.config.cjs >/dev/null; then
    echo "  Skipping stylelint: no Stylelint config between the file and the project root" >&2
  elif command -v npx &>/dev/null; then
    log_tool_start "stylelint"
    TOOLS_RUN+=("stylelint")
    STYLELINT_OUTPUT=""
    STYLELINT_EXIT=0
    STYLELINT_OUTPUT=$(npx_tool stylelint "$FILE_PATH" 2>&1) || STYLELINT_EXIT=$?

    if [[ "$STYLELINT_EXIT" -ne 0 ]] && is_js_setup_failure "$STYLELINT_OUTPUT"; then
      echo "  stylelint could not load its config here, so the file was not checked:" >&2
      echo "$STYLELINT_OUTPUT" | head -n 5 >&2
    elif [[ "$STYLELINT_EXIT" -ne 0 ]]; then
      echo "$STYLELINT_OUTPUT" >&2
      ERRORS=$((ERRORS + 1))
    fi
    log_tool_result "stylelint" "$STYLELINT_EXIT"
  else
    echo "  Skipping stylelint: npx not found" >&2
  fi
fi

# ── Summary & exit ───────────────────────────────────────────────────────────
log_summary

if [[ "$ERRORS" -gt 0 ]]; then
  exit 2
fi

if [[ -n "$NOTE" ]]; then
  jq -cn --arg note "$NOTE" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $note}}'
fi
exit 0