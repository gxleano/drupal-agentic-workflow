#!/usr/bin/env bash
#
# Smoke test: install drupal-agentic-workflow into throwaway fixture projects
# and assert what lands on disk, that a re-run never touches the instruction
# files, and that the generated phpstan.neon loads phpstan-drupal.
#
set -euo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAW="$REPO/bin/daw"

PASS=0
FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $1" >&2; FAIL=$((FAIL + 1)); }

# Assert a file contains / does not contain a fixed string.
has()    { grep -qF "$2" "$1" && ok "$3" || bad "$3"; }
hasnot() { grep -qF "$2" "$1" && bad "$3" || ok "$3"; }
exists() { [[ -e "$1" ]] && ok "$2" || bad "$2"; }
absent() { [[ -e "$1" ]] && bad "$2" || ok "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

new_project() {
  local dir="$1" json="$2"
  mkdir -p "$dir/web/modules/custom"
  printf '%s\n' "$json" > "$dir/composer.json"
}

echo "── install ─────────────────────────────────────"
PROJ="$TMP/mysite"
new_project "$PROJ" '{ "name": "acme/mysite", "require": { "drupal/core-recommended": "^11" } }'
# Hermetic: no tool install, so no network and no prompts.
"$DAW" install "$PROJ" --skip-tools >/dev/null

exists "$PROJ/AGENTS.md"                               "AGENTS.md created"
has    "$PROJ/AGENTS.md" "## Commands"                 "AGENTS.md is the short template"
hasnot "$PROJ/AGENTS.md" "Critical Code Rules"         "no old rules block"
[[ "$(cat "$PROJ/CLAUDE.md")" == "@AGENTS.md" ]] && ok "CLAUDE.md only imports AGENTS.md" \
                                                 || bad "CLAUDE.md only imports AGENTS.md"
n=$(wc -l < "$PROJ/AGENTS.md" | tr -d ' ')
[[ "$n" -le 150 ]] && ok "AGENTS.md template is short ($n lines)" || bad "AGENTS.md template too long ($n lines)"

for h in pre-bash-guard.sh post-generation-lint.sh post-session-phpstan.sh; do
  [[ -x "$PROJ/.claude/hooks/$h" ]] && ok "hook $h executable" || bad "hook $h executable"
done
exists "$PROJ/.claude/hooks/lib/php-tools.sh"           "hook library installed (hooks source it)"
exists "$PROJ/.claude/settings.json"                    "settings.json installed"
absent "$PROJ/.claude/skills"                           "no skills installed"
[[ -x "$PROJ/.claude/tools/site-api.sh" ]] && ok "site-api.sh installed" || bad "site-api.sh installed"
exists "$PROJ/.claude/tools/site-api.php"               "site-api.php installed"
absent "$PROJ/.claude/site-api.json"                    "site-api.json not generated at setup"
for f in conventions.md project-map.md stack.json glossary.md external-systems.md; do
  absent "$PROJ/.claude/$f"                             "no generated $f"
done
has "$PROJ/.gitignore" ".claude/site-api.json"          ".gitignore ignores site-api.json"

echo "── phpstan.neon ────────────────────────────────"
has    "$PROJ/phpstan.neon" "web/modules/custom"        "scans the custom modules"
hasnot "$PROJ/phpstan.neon" "drupal:"                   "no drupal: params without phpstan-drupal"

DRUPAL="$TMP/with-phpstan-drupal"
new_project "$DRUPAL" '{ "require": { "drupal/core-recommended": "^11" }, "require-dev": { "phpstan/phpstan": "^2", "mglaman/phpstan-drupal": "^2", "phpstan/phpstan-deprecation-rules": "^2" } }'
"$DAW" install "$DRUPAL" --skip-tools >/dev/null
has "$DRUPAL/phpstan.neon" "vendor/mglaman/phpstan-drupal/extension.neon" "includes phpstan-drupal when no extension installer"
has "$DRUPAL/phpstan.neon" "phpstan-deprecation-rules/rules.neon"         "includes deprecation rules"
has "$DRUPAL/phpstan.neon" "drupal_root: web"                             "sets drupal_root"

INSTALLER="$TMP/with-installer"
new_project "$INSTALLER" '{ "require": { "drupal/core-recommended": "^11" }, "require-dev": { "mglaman/phpstan-drupal": "^2", "phpstan/extension-installer": "^1" } }'
"$DAW" install "$INSTALLER" --skip-tools >/dev/null
hasnot "$INSTALLER/phpstan.neon" "includes:"            "no includes when the extension installer loads them"
has    "$INSTALLER/phpstan.neon" "drupal_root: web"     "still sets drupal_root"

BROKEN="$TMP/broken-neon"
new_project "$BROKEN" '{ "require": { "drupal/core-recommended": "^11" }, "require-dev": { "mglaman/phpstan-drupal": "^2" } }'
printf 'parameters:\n  level: 2\n  drupal:\n    drupal_root: web\n' > "$BROKEN/phpstan.neon"
out=$("$DAW" install "$BROKEN" --skip-tools 2>&1 >/dev/null || true)
grep -qF "nothing loads phpstan-drupal" <<< "$out" && ok "warns about an existing neon that cannot load phpstan-drupal" \
                                               || bad "warns about an existing neon that cannot load phpstan-drupal"

echo "── re-run leaves instruction files alone ───────"
echo "Team-written line." >> "$PROJ/AGENTS.md"
"$DAW" update "$PROJ" >/dev/null
has "$PROJ/AGENTS.md" "Team-written line."              "AGENTS.md edits survive update"
n=$(grep -cxF ".claude/site-api.json" "$PROJ/.gitignore")
[[ "$n" -eq 1 ]] && ok ".gitignore entry added once" || bad ".gitignore entry added $n times"

echo "── old managed AGENTS.md ───────────────────────"
LEGACY="$TMP/legacy"
new_project "$LEGACY" '{ "require": { "drupal/core-recommended": "^11" } }'
printf '# AGENTS.md\n<!-- drupal-agentic-workflow:start -->\nold rules\n<!-- drupal-agentic-workflow:end -->\n' > "$LEGACY/AGENTS.md"
out=$("$DAW" update "$LEGACY" 2>&1 >/dev/null || true)
has "$LEGACY/AGENTS.md" "old rules"                     "old AGENTS.md is not rewritten"
grep -qF "old managed block" <<< "$out" && ok "warns that the old block is no longer updated" \
                                        || bad "warns that the old block is no longer updated"

echo "── settings.json with other hooks ──────────────"
MERGE="$TMP/merge"
new_project "$MERGE" '{ "require": { "drupal/core-recommended": "^11" } }'
mkdir -p "$MERGE/.claude"
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"node other.cjs"}]}]}}' > "$MERGE/.claude/settings.json"
"$DAW" install "$MERGE" --skip-tools >/dev/null
S="$MERGE/.claude/settings.json"
jq -e '[.. | objects | .command? // empty] | index("node other.cjs")' "$S" >/dev/null \
  && ok "keeps the project's own hooks" || bad "keeps the project's own hooks"
jq -e '.permissions.allow == ["Bash(ls:*)"]' "$S" >/dev/null && ok "keeps the project's permissions" || bad "keeps the project's permissions"
for h in pre-bash-guard.sh post-generation-lint.sh post-session-phpstan.sh; do
  grep -qF "$h" "$S" && ok "adds $h to an existing settings.json" || bad "adds $h to an existing settings.json"
done
before=$(cat "$S")
"$DAW" update "$MERGE" >/dev/null
[[ "$(cat "$S")" == "$before" ]] && ok "a second run adds nothing" || bad "a second run adds nothing"
"$DAW" update "$MERGE" --force >/dev/null
jq -e '[.. | objects | .command? // empty] | index("node other.cjs")' "$S" >/dev/null \
  && ok "--force still keeps the project's own hooks" || bad "--force still keeps the project's own hooks"

echo ""
echo "smoke: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
