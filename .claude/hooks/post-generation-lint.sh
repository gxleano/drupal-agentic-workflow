#!/usr/bin/env bash
#
# Post-generation hook for Claude Code.
# Detects changed file types and runs the appropriate linters,
# plus fast grep-based security & performance checks for PHP.
# Exit code 2 = blocking error (fed back to Claude as feedback).
#
set -euo pipefail

# ── Read hook input from stdin ───────────────────────────────────────────────
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ── Resolve project root ────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# ── Helpers ──────────────────────────────────────────────────────────────────
ERRORS=0
TOOLS_RUN=()

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

is_prettier_target() {
  is_javascript && return 0
  is_stylesheet && return 0
  is_twig && return 0
  case "$EXT" in
    yaml|yml|json) return 0 ;;
  esac
  return 1
}

# Skip files outside the project or in vendor/contrib/core directories.
is_lintable() {
  case "$FILE_PATH" in
    */vendor/*|*/node_modules/*|*/web/core/*|*/web/modules/contrib/*|*/web/themes/contrib/*|*/web/profiles/*)
      return 1 ;;
  esac
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

  # Make the path relative to the project for ddev commands.
  REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

  # --- PHPCBF (auto-fix) ---
  log_tool_start "phpcbf"
  TOOLS_RUN+=("phpcbf")
  PHPCBF_OUTPUT=""
  PHPCBF_EXIT=0
  PHPCBF_OUTPUT=$(ddev exec phpcbf --standard=Drupal,DrupalPractice \
    --extensions=php,module,inc,install,test,profile,theme \
    "$REL_PATH" 2>&1) || PHPCBF_EXIT=$?

  # phpcbf exit 1 = fixes applied (success), exit 2 = unfixable errors
  if [[ "$PHPCBF_EXIT" -eq 1 ]]; then
    echo "  phpcbf: auto-fixed coding standard violations" >&2
  fi
  log_tool_result "phpcbf" 0  # phpcbf is best-effort, not a blocker

  # --- PHPCS ---
  log_tool_start "phpcs"
  TOOLS_RUN+=("phpcs")
  PHPCS_OUTPUT=""
  PHPCS_EXIT=0
  PHPCS_OUTPUT=$(ddev exec phpcs --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,test,profile,theme "$REL_PATH" 2>&1) || PHPCS_EXIT=$?

  if [[ "$PHPCS_EXIT" -ne 0 ]]; then
    echo "$PHPCS_OUTPUT" >&2
    ERRORS=$((ERRORS + 1))
  fi
  log_tool_result "phpcs" "$PHPCS_EXIT"

  # --- Security & Performance scan (local grep, no Docker — ~10-50ms) ---
  log_tool_start "security-perf-scan"
  TOOLS_RUN+=("security-perf-scan")
  SCAN_ERRORS=0

  # Helper: scan for a pattern (skips comment lines) and report.
  # Uses grep -nE (POSIX extended regex) for macOS compatibility.
  scan_pattern() {
    local category="$1"
    local pattern="$2"
    local message="$3"
    local matches
    # Strip leading comment lines to reduce false positives, then grep.
    matches=$(sed -E \
      -e 's|^[[:space:]]*/\*.*\*/[[:space:]]*$||' \
      -e 's|^[[:space:]]*//.*$||' \
      -e 's|^[[:space:]]*\*.*$||' \
      -e 's|^[[:space:]]*#[^!].*$||' \
      "$FILE_PATH" | grep -nE "$pattern" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      while IFS= read -r match; do
        echo "  [$category] Line ${match%%:*}: $message" >&2
        echo "    > ${match#*:}" >&2
      done <<< "$matches"
      SCAN_ERRORS=$((SCAN_ERRORS + 1))
    fi
  }

  # ── SECURITY: high-confidence patterns (near-zero false positives) ─────

  scan_pattern "SECURITY" 'eval[[:space:]]*\(' \
    "eval() is a code injection risk. Use a safer alternative."
  scan_pattern "SECURITY" 'shell_exec[[:space:]]*\(' \
    "shell_exec() — command injection risk. Use Symfony Process if needed."
  scan_pattern "SECURITY" 'passthru[[:space:]]*\(' \
    "passthru() — command injection risk. Use Symfony Process if needed."
  scan_pattern "SECURITY" 'proc_open[[:space:]]*\(' \
    "proc_open() — command injection risk. Use Symfony Process if needed."
  scan_pattern "SECURITY" '[^a-zA-Z_]popen[[:space:]]*\(' \
    "popen() — command injection risk. Use Symfony Process if needed."
  scan_pattern "SECURITY" '\$_(GET|POST|REQUEST|COOKIE)' \
    "Direct superglobal access. Use \\\$request->query/request->get() via RequestStack."
  scan_pattern "SECURITY" 'unserialize[[:space:]]*\(' \
    "unserialize() — object injection risk. Use json_decode() or Drupal serialization."
  scan_pattern "SECURITY" '[^a-zA-Z_]extract[[:space:]]*\(' \
    "extract() can overwrite variables. Use explicit array access instead."

  # ── PERFORMANCE: high-confidence patterns ──────────────────────────────

  # \Drupal:: in src/ service classes — must use DI.
  if [[ "$FILE_PATH" == */src/* ]]; then
    scan_pattern "PERFORMANCE" '\\Drupal::' \
      "\\Drupal:: service locator in src/ class. Inject via constructor instead."
  fi

  # Entity queries without accessCheck() — required in Drupal 11.
  if grep -qE '->getQuery\(|->getAggregateQuery\(' "$FILE_PATH" 2>/dev/null; then
    if ! grep -qE '->accessCheck\(' "$FILE_PATH" 2>/dev/null; then
      scan_pattern "PERFORMANCE" '->getQuery\(|->getAggregateQuery\(' \
        "Entity query without ->accessCheck(TRUE). Required by Drupal 11."
    fi
  fi

  if [[ "$SCAN_ERRORS" -gt 0 ]]; then
    ERRORS=$((ERRORS + SCAN_ERRORS))
  fi
  log_tool_result "security-perf-scan" "$SCAN_ERRORS"

fi

# ── Formatting: Prettier ──────────────────────────────────────────────────────
if is_prettier_target; then
  if command -v npx &>/dev/null && npx prettier --version &>/dev/null; then
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
      PRETTIER_OUTPUT=$(npx prettier --write "$FILE_PATH" 2>&1) || PRETTIER_EXIT=$?

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
  if command -v npx &>/dev/null; then
    log_tool_start "eslint"
    TOOLS_RUN+=("eslint")
    ESLINT_OUTPUT=""
    ESLINT_EXIT=0
    ESLINT_OUTPUT=$(npx eslint --no-error-on-unmatched-pattern "$FILE_PATH" 2>&1) || ESLINT_EXIT=$?

    if [[ "$ESLINT_EXIT" -ne 0 ]]; then
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
  if command -v npx &>/dev/null; then
    log_tool_start "stylelint"
    TOOLS_RUN+=("stylelint")
    STYLELINT_OUTPUT=""
    STYLELINT_EXIT=0
    STYLELINT_OUTPUT=$(npx stylelint "$FILE_PATH" 2>&1) || STYLELINT_EXIT=$?

    if [[ "$STYLELINT_EXIT" -ne 0 ]]; then
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

exit 0