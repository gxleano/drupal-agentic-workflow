#!/usr/bin/env bash
#
# Test runner for the drupal-agentic-workflow tooling itself.
# Stages (each is skipped gracefully if its tool is unavailable locally; CI
# installs them all):
#   1. shellcheck   — static analysis of every shell script
#   2. bash -n      — syntax check of every shell script
#   3. node --test  — unit tests for the .mjs generators
#   4. smoke.sh     — end-to-end setup.sh install + idempotency
#
set -uo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

FAILED=0
stage() { echo ""; echo "═══ $1 ═══"; }
fail()  { echo "✗ $1 FAILED" >&2; FAILED=1; }

# Collect shell scripts: bin/, hooks, hook lib, and tests/*.sh.
# Built without `mapfile` (absent on macOS's bash 3.2); non-matching globs are
# filtered out by the `-f` test.
SH_FILES=()
for f in bin/setup.sh bin/daw .claude/hooks/*.sh .claude/hooks/lib/*.sh tests/*.sh; do
  [[ -f "$f" ]] && SH_FILES+=("$f")
done

stage "bash -n (syntax)"
for f in "${SH_FILES[@]}"; do
  [[ -f "$f" ]] || continue
  bash -n "$f" && echo "  ok $f" || fail "bash -n $f"
done

stage "shellcheck"
if command -v shellcheck &>/dev/null; then
  # -x follows `source`d files (e.g. hooks sourcing lib/php-tools.sh).
  # Gate at warning+; info/style (e.g. SC2094 append-after-read) are noisy
  # false positives for this codebase.
  shellcheck -x --severity=warning "${SH_FILES[@]}" && echo "  shellcheck clean (warning+)" || fail "shellcheck"
else
  echo "  (shellcheck not installed — skipped)"
fi

stage "node --test"
if command -v node &>/dev/null; then
  # Expand the glob in bash (not in node) so this works regardless of Node
  # version — node's own `--test` glob support only landed in Node 21+.
  TEST_FILES=()
  for f in tests/*.test.mjs; do
    [[ -f "$f" ]] && TEST_FILES+=("$f")
  done
  if [[ "${#TEST_FILES[@]}" -gt 0 ]]; then
    node --test "${TEST_FILES[@]}" || fail "node --test"
  else
    echo "  (no *.test.mjs files — skipped)"
  fi
else
  echo "  (node not installed — skipped)"
fi

stage "smoke (setup.sh e2e)"
bash tests/smoke.sh || fail "smoke"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL STAGES PASSED"
else
  echo "ONE OR MORE STAGES FAILED" >&2
fi
exit "$FAILED"
