#!/usr/bin/env bash
#
# Smoke test: install drupal-agentic-workflow into a throwaway fixture project
# and assert that AGENTS.md carries the rules, CLAUDE.md imports it, a second
# run is idempotent, and a CLAUDE.md-centric install upgrades cleanly.
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/mysite"
mkdir -p "$PROJ/web/modules/custom"
cat > "$PROJ/composer.json" <<'JSON'
{ "name": "acme/mysite", "require": { "drupal/core-recommended": "^11" } }
JSON

echo "── install ─────────────────────────────────────"
# Fast, hermetic: no tool install, no detection (network/drush), no prompts.
"$DAW" install "$PROJ" --skip-tools --skip-detect --skip-ai-context --skip-followups >/dev/null

CLAUDE="$PROJ/CLAUDE.md"
AGENTS="$PROJ/AGENTS.md"

[[ -f "$CLAUDE" ]] && ok "CLAUDE.md created" || bad "CLAUDE.md created"
[[ -f "$AGENTS" ]] && ok "AGENTS.md created" || bad "AGENTS.md created"

echo "── AGENTS.md content (canonical) ───────────────"
has    "$AGENTS" "Critical Code Rules"     "holds the shared Drupal rules"
has    "$AGENTS" "Detailed patterns"       "keeps agent-agnostic Detailed patterns"
hasnot "$AGENTS" "Skills Reference"        "drops the Claude-only block"
hasnot "$AGENTS" "daw:claude-only"         "strips claude-only markers"
has    "$AGENTS" "## Custom Modules"       "holds the project sections"
has    "$AGENTS" "version-guide-pointer"   "holds the version-guide pointer"

echo "── CLAUDE.md content (imports AGENTS.md) ───────"
has    "$CLAUDE" "@AGENTS.md"              "imports AGENTS.md"
has    "$CLAUDE" "Skills Reference"        "keeps Claude-only Skills Reference"
hasnot "$CLAUDE" "Critical Code Rules"     "does not duplicate the shared rules"
hasnot "$CLAUDE" "daw:claude-only"         "strips claude-only markers"
hasnot "$CLAUDE" "## Custom Modules"       "does not duplicate the project sections"
hasnot "$CLAUDE" "version-guide-pointer"   "does not duplicate the version-guide pointer"

echo "── idempotent update ───────────────────────────"
"$DAW" update "$PROJ" --skip-detect >/dev/null
for f in "$CLAUDE" "$AGENTS"; do
  n="$(grep -cF "drupal-agentic-workflow:start" "$f" || true)"
  [[ "$n" -eq 1 ]] && ok "$(basename "$f"): exactly one managed block after re-run" \
                   || bad "$(basename "$f"): expected 1 managed block, found $n"
done
n="$(grep -c '^## Custom Modules' "$AGENTS" || true)"
[[ "$n" -eq 1 ]] && ok "AGENTS.md: project sections added once" \
                 || bad "AGENTS.md: expected 1 Custom Modules section, found $n"

echo "── upgrade from CLAUDE.md-centric layout ───────"
# A project set up by an earlier version: full rules + project sections +
# version-guide pointer in CLAUDE.md, and a rules-only AGENTS.md.
LEGACY="$TMP/legacy"
mkdir -p "$LEGACY/web/modules/custom"
cp "$PROJ/composer.json" "$LEGACY/composer.json"
cat > "$LEGACY/CLAUDE.md" <<'MD'
# CLAUDE.md

Team intro kept by the upgrade.

<!-- drupal-agentic-workflow:start -->

## Critical Code Rules (Always Follow)

<!-- drupal-agentic-workflow:end -->

## Custom Modules

- **acme_core**: team-written description

<!-- drupal-agentic-workflow: version-guide-pointer -->
See `.claude/drupal-version-guide.md` for version-specific patterns; prefer it over generic Drupal advice.
MD
cat > "$LEGACY/AGENTS.md" <<'MD'
# AGENTS.md

<!-- drupal-agentic-workflow:start -->

## Critical Code Rules (Always Follow)

<!-- drupal-agentic-workflow:end -->
MD
"$DAW" update "$LEGACY" --skip-detect >/dev/null
has    "$LEGACY/CLAUDE.md" "Team intro kept by the upgrade." "keeps user content outside the block"
has    "$LEGACY/CLAUDE.md" "@AGENTS.md"                   "managed block now imports AGENTS.md"
hasnot "$LEGACY/CLAUDE.md" "Critical Code Rules"          "rules removed from CLAUDE.md"
has    "$LEGACY/CLAUDE.md" "team-written description"     "existing project sections left in place"
hasnot "$LEGACY/CLAUDE.md" "version-guide-pointer"        "version-guide pointer moved out of CLAUDE.md"
has    "$LEGACY/AGENTS.md" "version-guide-pointer"        "version-guide pointer now in AGENTS.md"
hasnot "$LEGACY/AGENTS.md" "## Custom Modules"            "no duplicate project sections in AGENTS.md"
has    "$LEGACY/AGENTS.md" "Detailed patterns"            "AGENTS.md block refreshed"

echo ""
echo "smoke: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
