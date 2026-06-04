#!/usr/bin/env bash
#
# Smoke test: install drupal-agentic-workflow into a throwaway fixture project
# and assert the CLAUDE.md / AGENTS.md managed blocks render correctly and that
# a second run is idempotent (no duplicated managed blocks).
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

echo "── CLAUDE.md content ───────────────────────────"
has    "$CLAUDE" "Skills Reference"        "keeps Claude-only Skills Reference"
hasnot "$CLAUDE" "Detailed patterns"       "drops the agents-only block"
hasnot "$CLAUDE" "daw:claude-only"         "strips claude-only markers"
hasnot "$CLAUDE" "daw:agents-only"         "strips agents-only markers"
has    "$CLAUDE" "Critical Code Rules"     "keeps shared Drupal rules"

echo "── AGENTS.md content ───────────────────────────"
has    "$AGENTS" "Detailed patterns"       "keeps agent-agnostic Detailed patterns"
hasnot "$AGENTS" "Skills Reference"        "drops the Claude-only block"
hasnot "$AGENTS" "daw:claude-only"         "strips claude-only markers"
hasnot "$AGENTS" "daw:agents-only"         "strips agents-only markers"
has    "$AGENTS" "Critical Code Rules"     "keeps shared Drupal rules"

echo "── idempotent update ───────────────────────────"
"$DAW" update "$PROJ" --skip-detect >/dev/null
for f in "$CLAUDE" "$AGENTS"; do
  n="$(grep -cF "drupal-agentic-workflow:start" "$f" || true)"
  [[ "$n" -eq 1 ]] && ok "$(basename "$f"): exactly one managed block after re-run" \
                   || bad "$(basename "$f"): expected 1 managed block, found $n"
done

echo ""
echo "smoke: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
