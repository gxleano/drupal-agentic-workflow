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

# Remember the file for the PHPStan hook, which analyses only what Claude
# changed in this session (see post-session-phpstan.sh).
EDITS_FILE=$(session_edits_file "$INPUT")
if [[ -n "$EDITS_FILE" && -f "$FILE_PATH" ]]; then
  echo "${FILE_PATH#"$PROJECT_DIR"/}" >> "$EDITS_FILE" 2>/dev/null || true
fi

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

# Text files cspell also reads (code files are covered by the checks above).
is_spellable() {
  case "$EXT" in
    yml|yaml|md|txt) return 0 ;;
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
if ! is_backend && ! is_javascript && ! is_stylesheet && ! is_prettier_target && ! is_spellable; then
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

# ── Frontend tooling ─────────────────────────────────────────────────────────
# Inside the docroot, ESLint, Stylelint, Prettier and cspell are Drupal core's
# own, with core's configs, the way drupal.org's GitLab CI runs them (`daw
# install` installs them with core's `yarn install`). A config of the
# project's own below the docroot wins over core's. Elsewhere, or without
# core's tools, the project's own install is used where it has a config.
CORE_JS=false
CORE_JS_MISSING=false
DOCROOT=""
if WEB_ROOT=$(drupal_web_root "$PROJECT_DIR"); then
  DOCROOT="$PROJECT_DIR"
  [[ "$WEB_ROOT" != "." ]] && DOCROOT="$PROJECT_DIR/$WEB_ROOT"
fi
if [[ -n "$DOCROOT" && "$FILE_PATH" == "$DOCROOT"/* ]]; then
  if core_js_available "$PROJECT_DIR"; then
    CORE_JS=true
  elif [[ -f "$PROJECT_DIR/$CORE_DIR/package.json" ]]; then
    CORE_JS_MISSING=true
  fi
fi
REL_FILE="${FILE_PATH#"$PROJECT_DIR"/}"

# The nearest of the config files in $@ strictly below the docroot: the
# project's own. The docroot's .eslintrc.json comes from core's scaffold.
own_config() {
  local found
  found=$(find_config "$@") || return 1
  [[ "$(dirname "$found")" == "$DOCROOT" || "$found" != "$DOCROOT"/* ]] && return 1
  echo "$found"
}

# Runs one of core's tools from the project root (in DDEV when it runs there).
core_tool() {
  local tool="$1"; shift
  php_exec_tool "$PROJECT_DIR" "$CORE_JS_RUNNER" "$CORE_DIR/node_modules/.bin/$tool" "$@"
}

# report_check NAME EXIT OUTPUT [HINT] — shared result handling: a tool that cannot
# load its config is reported, a real finding is sent back to Claude.
report_check() {
  local name="$1" rc="$2" out="$3" hint="${4:-}"
  if [[ "$rc" -ne 0 ]] && is_js_setup_failure "$out"; then
    echo "  $name could not load its config here, so the file was not checked:" >&2
    echo "$out" | head -n 5 >&2
  elif [[ "$rc" -ne 0 ]]; then
    echo "$out" >&2
    [[ -n "$hint" ]] && echo "  $hint" >&2
    ERRORS=$((ERRORS + 1))
  fi
  log_tool_result "$name" "$rc"
}

if [[ "$CORE_JS_MISSING" == true ]] && { is_javascript || is_stylesheet; }; then
  echo "  Drupal core's JS tools are not installed, so ESLint, Stylelint, Prettier" >&2
  echo "  and cspell use the project's own, if any. Install them: vendor/bin/daw install" >&2
fi

# --- Prettier (formats; never on a submodule) -------------------------------
PRETTIER_CONFIGS=(.prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml .prettierrc.js
  .prettierrc.cjs .prettierrc.mjs prettier.config.js prettier.config.cjs prettier.config.mjs)
if is_prettier_target && [[ -z "$SUBMODULE" ]]; then
  if [[ "$CORE_JS" == true ]] && is_twig; then
    echo "  Skipping prettier for Twig: core's Prettier has no Twig plugin" >&2
  elif [[ "$CORE_JS" == true ]]; then
    log_file "$FILE_PATH" "formatting (Prettier, Drupal core)"
    log_tool_start "prettier"
    TOOLS_RUN+=("prettier")
    PRETTIER_ARGS=(--write)
    own_config "${PRETTIER_CONFIGS[@]}" >/dev/null || PRETTIER_ARGS+=(--config "$CORE_DIR/.prettierrc.json")
    PRETTIER_EXIT=0
    PRETTIER_OUTPUT=$(core_tool prettier "${PRETTIER_ARGS[@]}" "$REL_FILE" 2>&1) || PRETTIER_EXIT=$?
    report_check prettier "$PRETTIER_EXIT" "$PRETTIER_OUTPUT"
  elif command -v npx &>/dev/null && npx_tool prettier --version &>/dev/null; then
    if is_twig && ! npm ls prettier-plugin-twig-melody &>/dev/null; then
      echo "  Skipping prettier for Twig: prettier-plugin-twig-melody not installed" >&2
    else
      log_file "$FILE_PATH" "formatting (Prettier)"
      log_tool_start "prettier"
      TOOLS_RUN+=("prettier")
      PRETTIER_EXIT=0
      PRETTIER_OUTPUT=$(npx_tool prettier --write "$FILE_PATH" 2>&1) || PRETTIER_EXIT=$?
      report_check prettier "$PRETTIER_EXIT" "$PRETTIER_OUTPUT"
    fi
  else
    echo "  Skipping prettier: not available" >&2
  fi
fi

# --- ESLint -----------------------------------------------------------------
if is_javascript; then
  log_file "$FILE_PATH" "frontend (JavaScript/TypeScript)"
  FLAT=$(find_config eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts || true)
  LEGACY_CONFIGS=(.eslintrc.json .eslintrc.js .eslintrc.cjs .eslintrc.yml .eslintrc.yaml .eslintrc)
  if [[ -z "$FLAT" && "$CORE_JS" == true ]]; then
    # Core's ESLint 8. Without a config of the project's own it lints like
    # drupal.org's CI: core's .eslintrc.passing.json.
    ESLINT_ARGS=(--no-error-on-unmatched-pattern --resolve-plugins-relative-to "$CORE_DIR")
    own_config "${LEGACY_CONFIGS[@]}" >/dev/null \
      || ESLINT_ARGS+=(--no-eslintrc -c "$CORE_DIR/.eslintrc.passing.json")
    log_tool_start "eslint (Drupal core)"
    TOOLS_RUN+=("eslint")
    ESLINT_EXIT=0
    ESLINT_OUTPUT=$(core_tool eslint "${ESLINT_ARGS[@]}" "$REL_FILE" 2>&1) || ESLINT_EXIT=$?
    report_check eslint "$ESLINT_EXIT" "$ESLINT_OUTPUT"
  elif [[ -z "$FLAT" ]] && ! find_config "${LEGACY_CONFIGS[@]}" >/dev/null; then
    # Without a config ESLint fails on any file, which says nothing about it.
    echo "  Skipping eslint: no ESLint config between the file and the project root" >&2
  elif command -v npx &>/dev/null; then
    log_tool_start "eslint"
    TOOLS_RUN+=("eslint")
    ESLINT_EXIT=0
    ESLINT_OUTPUT=$(npx_tool eslint --no-error-on-unmatched-pattern "$FILE_PATH" 2>&1) || ESLINT_EXIT=$?
    report_check eslint "$ESLINT_EXIT" "$ESLINT_OUTPUT"
  else
    echo "  Skipping eslint: npx not found" >&2
  fi
fi

# --- Stylelint --------------------------------------------------------------
if is_stylesheet; then
  log_file "$FILE_PATH" "frontend (CSS/SCSS)"
  STYLELINT_CONFIGS=(.stylelintrc .stylelintrc.json .stylelintrc.js .stylelintrc.cjs .stylelintrc.yml
    .stylelintrc.yaml stylelint.config.js stylelint.config.mjs stylelint.config.cjs)
  if [[ "$CORE_JS" == true ]]; then
    STYLELINT_ARGS=(--config-basedir "$CORE_DIR")
    own_config "${STYLELINT_CONFIGS[@]}" >/dev/null \
      || STYLELINT_ARGS+=(--config "$CORE_DIR/.stylelintrc.json")
    log_tool_start "stylelint (Drupal core)"
    TOOLS_RUN+=("stylelint")
    STYLELINT_EXIT=0
    STYLELINT_OUTPUT=$(core_tool stylelint "${STYLELINT_ARGS[@]}" "$REL_FILE" 2>&1) || STYLELINT_EXIT=$?
    report_check stylelint "$STYLELINT_EXIT" "$STYLELINT_OUTPUT"
  elif ! find_config "${STYLELINT_CONFIGS[@]}" >/dev/null; then
    echo "  Skipping stylelint: no Stylelint config between the file and the project root" >&2
  elif command -v npx &>/dev/null; then
    log_tool_start "stylelint"
    TOOLS_RUN+=("stylelint")
    STYLELINT_EXIT=0
    STYLELINT_OUTPUT=$(npx_tool stylelint "$FILE_PATH" 2>&1) || STYLELINT_EXIT=$?
    report_check stylelint "$STYLELINT_EXIT" "$STYLELINT_OUTPUT"
  else
    echo "  Skipping stylelint: npx not found" >&2
  fi
fi

# --- cspell (as drupal.org's CI configures it) ------------------------------
# Mirrors gitlab_templates' cspell job: its default config (built-in and core
# dictionaries, flagged words, min word length 4), every machine-name part of
# the module's .info.yml files and a few fixed words as allowed, the module's
# own .cspell.json if it has one, and the words in .cspell-project-words.txt.
# https://project.pages.drupalcode.org/gitlab_templates/jobs/cspell/
CSPELL_STANDARD_FILE=false
case "$(basename "$FILE_PATH" | tr '[:upper:]' '[:lower:]')" in
  .*.json|package.json|yarn.lock|phpstan*|.*ignore|license*|copyright*|maintainers*|changelog*|composer.*)
    CSPELL_STANDARD_FILE=true ;;
esac
if [[ "$CORE_JS" == true && "$CSPELL_STANDARD_FILE" == false ]] \
    && { is_backend || is_javascript || is_stylesheet || is_twig || is_spellable; }; then
  log_tool_start "cspell (Drupal core)"
  TOOLS_RUN+=("cspell")
  # The extension the file belongs to: the nearest directory with an .info.yml.
  MODULE_DIR="$(dirname "$FILE_PATH")"
  while [[ "$MODULE_DIR" != "$DOCROOT" && "$MODULE_DIR" == "$DOCROOT"/* ]] \
      && ! compgen -G "$MODULE_DIR/*.info.yml" >/dev/null; do
    MODULE_DIR="$(dirname "$MODULE_DIR")"
  done
  [[ "$MODULE_DIR" == "$DOCROOT" ]] && MODULE_DIR=""
  MODULE_WORDS="[]"
  OWN_CSPELL=""
  WORDS=""
  if [[ -n "$MODULE_DIR" ]]; then
    MODULE_WORDS=$(find "$MODULE_DIR" -name '*.info.yml' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null \
      | sed -E 's|.*/||; s|\.info\.yml$||' | tr '_' '\n' | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')
    [[ -f "$MODULE_DIR/.cspell.json" ]] && OWN_CSPELL="${MODULE_DIR#"$PROJECT_DIR"/}/.cspell.json"
    [[ -f "$MODULE_DIR/.cspell-project-words.txt" ]] && WORDS="${MODULE_DIR#"$PROJECT_DIR"/}/.cspell-project-words.txt"
  fi
  if [[ "$CORE_JS_RUNNER" == "ddev exec" ]]; then
    # DDEV mounts the project at /var/www/html.
    BASE="/var/www/html"
    CSPELL_CFG="/tmp/claude-cspell-$$.json"
  else
    BASE="$PROJECT_DIR"
    CSPELL_CFG="${TMPDIR:-/tmp}/claude-cspell-$$.json"
  fi
  CSPELL_JSON=$(jq -cn --arg base "$BASE" --arg core "$CORE_DIR" --arg own "$OWN_CSPELL" \
    --arg words "$WORDS" --argjson module "$MODULE_WORDS" '
    {
      language: "en-US",
      allowCompoundWords: false,
      minWordLength: 4,
      flagWords: [
        "blacklist->blocklist, denylist", "blacklists->blocklists, denylists",
        "blacklist'"'"'s->blocklist'"'"'s, denylist'"'"'s", "blacklisted->blocklisted, denylisted",
        "e-mail", "grey", "queuing", "whitelist:allowlist", "whitelists:allowlists",
        "whitelist'"'"'s:allowlist'"'"'s", "whitelisted:allowlisted"
      ],
      overrides: [{filename: "**/{*.engine,*.inc,*.install,*.module,*.profile,*.theme}", languageId: "php"}],
      dictionaryDefinitions: ([
        {name: "drupal", path: "\($base)/\($core)/misc/cspell/drupal-dictionary.txt"},
        {name: "dictionary", path: "\($base)/\($core)/misc/cspell/dictionary.txt"}
      ] + (if $words == "" then [] else [{name: "project-words", path: "\($base)/\($words)"}] end)),
      dictionaries: (["companies", "fonts", "html", "php", "softwareTerms", "misc", "typescript", "node",
        "css", "bash", "filetypes", "npm", "lorem-ipsum", "sql", "fullstack", "drupal", "dictionary"]
        + (if $words == "" then [] else ["project-words"] end)),
      words: ($module + ["lando", "ddev", "endapply", "nightwatchjs", "testgroup", "testgroups",
        "backlinks", "mdhash", "uploaders", "vocabs", "curlopt", "returntransfer", "curle",
        "customrequest", "failonerror", "postfields", "followlocation", "colourdefinitionsniff",
        "seletorsingleline", "teamplatespacingaftercomment", "tforvalue", "trhowscommentindentation",
        "unecessaryfiledeclaration", "blocklisted", "flagwords", "mkdocs", "autorun", "runtests",
        "dcms", "browsertest", "chromedriver", "dockerhub", "drupalorg", "drush", "simpletest",
        "minwordlength", "iid", "xdg"])
    }
    + (if $own == "" then {} else {import: ["\($base)/\($own)"]} end)')
  CSPELL_EXIT=0
  if [[ "$CORE_JS_RUNNER" == "ddev exec" ]]; then
    # The config is written inside the container, where cspell runs.
    CSPELL_OUTPUT=$(cd "$PROJECT_DIR" && ddev exec "printf '%s' $(printf '%q' "$CSPELL_JSON") > $CSPELL_CFG \
      && $CORE_DIR/node_modules/.bin/cspell -c $CSPELL_CFG --no-progress --no-summary --no-must-find-files $(printf '%q' "$REL_FILE"); \
      rc=\$?; rm -f $CSPELL_CFG; exit \$rc" 2>&1) || CSPELL_EXIT=$?
  else
    printf '%s' "$CSPELL_JSON" > "$CSPELL_CFG"
    CSPELL_OUTPUT=$(core_tool cspell -c "$CSPELL_CFG" --no-progress --no-summary --no-must-find-files "$REL_FILE" 2>&1) || CSPELL_EXIT=$?
    rm -f "$CSPELL_CFG"
  fi
  # ddev exec adds its own "Failed to execute command" line: drop it.
  CSPELL_OUTPUT=$(grep -v 'Failed to execute command' <<< "$CSPELL_OUTPUT" || true)
  report_check cspell "$CSPELL_EXIT" "$CSPELL_OUTPUT" \
    "Fix the typos. Add real words (names, terms) to ${WORDS:-.cspell-project-words.txt in the module root}, one per line."
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