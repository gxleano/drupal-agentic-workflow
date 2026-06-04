#!/usr/bin/env bash
#
# Shared PHP tooling resolution for Claude Code hooks.
#
# Lets the lint/phpstan hooks work both inside a containerised Drupal site
# (DDEV) and directly inside a standalone contrib module/theme/profile repo
# that has no Drupal installation — by falling back to local binaries.
#
# Resolution order for any tool (phpcs, phpcbf, phpstan, …):
#   1. DDEV          — `ddev exec <tool>` (matches the project's CI toolchain)
#   2. vendor/bin    — the repo's own Composer dev dependency
#   3. $PATH         — a globally exported binary
#   4. global Composer bin — ~/.composer or ~/.config/composer (not on $PATH)
#
# This file is meant to be sourced, not executed:
#   source "$(dirname "$0")/lib/php-tools.sh"

# php_resolve_tool sets PHP_TOOL_* globals as its return channel; they are read
# by the sourcing hooks, not within this file — so SC2034 (unused) is expected.
# shellcheck disable=SC2034

# Known global Composer bin directories to probe when a tool is neither in the
# repo's vendor/bin nor already on $PATH.
_php_tools_composer_bin_dirs() {
  [[ -n "${COMPOSER_HOME:-}" ]] && echo "$COMPOSER_HOME/vendor/bin"
  echo "$HOME/.composer/vendor/bin"
  echo "$HOME/.config/composer/vendor/bin"
}

# Is this project wired for DDEV *and* is the container currently running?
# (If DDEV is configured but stopped, `ddev exec` would fail — so we report
# false and let the caller fall back to a local binary.)
php_ddev_available() {
  local project_dir="$1"
  command -v ddev &>/dev/null \
    && [[ -f "$project_dir/.ddev/config.yaml" ]] \
    && ddev status 2>/dev/null | grep -q "running"
}

# Resolve a PHP tool, honouring the order documented above.
#
#   php_resolve_tool <project_dir> <tool>
#
# On success returns 0 and sets these globals:
#   PHP_TOOL_FOUND   = true
#   PHP_TOOL_RUNNER  = "ddev exec"  (empty for a local binary)
#   PHP_TOOL_BIN     = "phpcs" | "/abs/path/to/phpcs"
#   PHP_TOOL_SOURCE  = ddev | vendor/bin | PATH | global-composer
# On failure returns 1 with PHP_TOOL_FOUND=false.
php_resolve_tool() {
  local project_dir="$1" tool="$2"
  PHP_TOOL_FOUND=false
  PHP_TOOL_RUNNER=""
  PHP_TOOL_BIN=""
  PHP_TOOL_SOURCE=""

  # 1) DDEV (containerised toolchain — matches CI exactly).
  if php_ddev_available "$project_dir"; then
    PHP_TOOL_FOUND=true
    PHP_TOOL_RUNNER="ddev exec"
    PHP_TOOL_BIN="$tool"
    PHP_TOOL_SOURCE="ddev"
    return 0
  fi

  # 2) Project-local Composer binary.
  if [[ -x "$project_dir/vendor/bin/$tool" ]]; then
    PHP_TOOL_FOUND=true
    PHP_TOOL_BIN="$project_dir/vendor/bin/$tool"
    PHP_TOOL_SOURCE="vendor/bin"
    return 0
  fi

  # 3) Tool already on $PATH (e.g. an exported global Composer install).
  if command -v "$tool" &>/dev/null; then
    PHP_TOOL_FOUND=true
    PHP_TOOL_BIN="$tool"
    PHP_TOOL_SOURCE="PATH"
    return 0
  fi

  # 4) Known global Composer bin directories not on $PATH.
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    if [[ -x "$dir/$tool" ]]; then
      PHP_TOOL_FOUND=true
      PHP_TOOL_BIN="$dir/$tool"
      PHP_TOOL_SOURCE="global-composer"
      return 0
    fi
  done < <(_php_tools_composer_bin_dirs)

  return 1
}

# Execute a resolved tool from the project root.
#
#   php_exec_tool <project_dir> <runner> <bin> [args...]
#
# <runner> intentionally word-splits ("ddev exec" → two argv); <bin> is quoted
# so binary paths containing spaces survive.
php_exec_tool() {
  local project_dir="$1" runner="$2" bin="$3"; shift 3
  # shellcheck disable=SC2086  # $runner ("ddev exec") must word-split.
  ( cd "$project_dir" && $runner "$bin" "$@" )
}

# Detect the kind of repository we're in.
#
#   php_project_context <project_dir>  ->  "site" | "module"
#
# "site"   = a full Drupal installation (has a docroot with core checked out).
# "module" = a standalone extension repo (an *.info.yml at the root, or a
#            composer.json of type drupal-module/theme/profile and no docroot).
php_project_context() {
  local project_dir="$1"

  # A full site has Drupal core checked out under a docroot (or at the root).
  if [[ -d "$project_dir/web/core" || -d "$project_dir/core" ]]; then
    echo "site"
    return
  fi

  # A standalone extension ships its definition file at (or near) the root.
  if compgen -G "$project_dir/*.info.yml" >/dev/null 2>&1; then
    echo "module"
    return
  fi

  if [[ -f "$project_dir/composer.json" ]] \
     && grep -qE '"type"[[:space:]]*:[[:space:]]*"drupal-(module|theme|profile)"' \
              "$project_dir/composer.json"; then
    echo "module"
    return
  fi

  # Default to the safer "site" assumption.
  echo "site"
}

# Locate phpstan-drupal's extension.neon so a synthesized config can include it.
#
#   php_find_phpstan_drupal <project_dir> <resolved_phpstan_bin>
#
# Echoes the absolute path to extension.neon, or nothing if not installed.
# Probes the repo's vendor/, the vendor/ that owns the resolved phpstan binary,
# and the global Composer vendor/ directories.
php_find_phpstan_drupal() {
  local project_dir="$1" bin="$2"
  local -a vendors=("$project_dir/vendor")

  # vendor/ that owns the resolved phpstan binary (…/vendor/bin/phpstan).
  if [[ "$bin" == */vendor/bin/phpstan ]]; then
    vendors+=("${bin%/bin/phpstan}")
  fi

  # Global Composer vendor dirs (parent of each bin dir).
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && vendors+=("${dir%/bin}")
  done < <(_php_tools_composer_bin_dirs)

  local v
  for v in "${vendors[@]}"; do
    if [[ -f "$v/mglaman/phpstan-drupal/extension.neon" ]]; then
      echo "$v/mglaman/phpstan-drupal/extension.neon"
      return 0
    fi
  done
  return 1
}
