#!/usr/bin/env bash
#
# Hook tests: feed each hook the JSON Claude Code sends and check the exit
# code. Exit 2 means "blocked / sent back to Claude"; 0 means "carry on".
#
set -euo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/.claude/hooks"

PASS=0
FAIL=0
ok()  { echo "  ✓ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ✗ $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git_q() { git -C "$1" -c user.email=t@example.com -c user.name=t "${@:2}" >/dev/null 2>&1; }

# expect_exit WANT LABEL HOOK PROJECT JSON
expect_exit() {
  local want="$1" label="$2" hook="$3" project="$4" json="$5" got=0
  echo "$json" | CLAUDE_PROJECT_DIR="$project" bash "$HOOKS/$hook" >/dev/null 2>&1 || got=$?
  [[ "$got" -eq "$want" ]] && ok "$label" || bad "$label (exit $got, want $want)"
}

bash_cmd() { jq -cn --arg c "$1" '{tool_input: {command: $c}}'; }

echo "── pre-bash-guard: secrets ─────────────────────"
P="$TMP/guard"
mkdir -p "$P"
git_q "$P" init
echo "x" > "$P/README.md"
git_q "$P" add README.md
git_q "$P" commit -m init
echo "SECRET=1" > "$P/.env"
echo "SECRET=" > "$P/.env.example"

expect_exit 2 "blocks git add .env"                  pre-bash-guard.sh "$P" "$(bash_cmd 'git add .env')"
expect_exit 2 "blocks git add -f settings.local.php" pre-bash-guard.sh "$P" "$(bash_cmd 'git add -f web/sites/default/settings.local.php')"
expect_exit 0 "allows git add .env.example"          pre-bash-guard.sh "$P" "$(bash_cmd 'git add .env.example')"
expect_exit 2 "blocks git add -A with an unignored .env" pre-bash-guard.sh "$P" "$(bash_cmd 'git add -A')"
echo ".env" > "$P/.gitignore"
expect_exit 0 "allows git add -A once .env is ignored"   pre-bash-guard.sh "$P" "$(bash_cmd 'git add -A')"
expect_exit 0 "allows a normal commit"               pre-bash-guard.sh "$P" "$(bash_cmd 'git commit -m "update docs"')"
git_q "$P" add -f .env
expect_exit 2 "blocks a commit with .env staged"     pre-bash-guard.sh "$P" "$(bash_cmd 'git commit -m wip')"
git_q "$P" reset -q
expect_exit 0 "allows git status"                    pre-bash-guard.sh "$P" "$(bash_cmd 'git status')"
expect_exit 2 "still blocks git reset --hard"        pre-bash-guard.sh "$P" "$(bash_cmd 'git reset --hard')"

echo "── post-generation-lint ────────────────────────"
L="$TMP/lint"
mkdir -p "$L/web/modules/custom/upstream/src" "$L/web/modules/custom/mine/src" "$L/vendor/bin"
printf '[submodule "upstream"]\n\tpath = web/modules/custom/upstream\n\turl = https://example.com/upstream.git\n' > "$L/.gitmodules"
echo '<?php' > "$L/web/modules/custom/upstream/src/A.php"
echo '<?php' > "$L/web/modules/custom/upstream/phpcs.xml.dist"
echo '<?php' > "$L/web/modules/custom/mine/src/B.php"
file_json() { jq -cn --arg f "$1" '{tool_input: {file_path: $f}}'; }
# Fake phpcs/phpcbf: log their arguments; exit with $FAKE_PHPCS / $FAKE_PHPCBF.
for t in phpcs phpcbf; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls"\nexit "${FAKE_%s:-0}"\n' \
    "$t" "$L" "$(echo "$t" | tr '[:lower:]' '[:upper:]')" > "$L/vendor/bin/$t"
  chmod +x "$L/vendor/bin/$t"
done
lint() {
  : > "$L/calls"
  out=$(file_json "$1" | CLAUDE_PROJECT_DIR="$L" bash "${2:-$HOOKS}/post-generation-lint.sh" 2>"$L/err") && rc=0 || rc=$?
}

lint "$L/web/modules/custom/mine/src/B.php"
[[ "$rc" -eq 0 ]] && grep -q '^phpcbf ' "$L/calls" && grep -q '^phpcs ' "$L/calls" \
  && ok "fixes and lints project-owned files" || bad "fixes and lints project-owned files (exit $rc)"

lint "$L/web/modules/custom/upstream/src/A.php"
grep -q '^phpcbf ' "$L/calls" && bad "never auto-fixes a submodule" || ok "never auto-fixes a submodule"
grep -q -- '--standard=web/modules/custom/upstream/phpcs.xml.dist' "$L/calls" \
  && ok "lints a submodule with its own ruleset" || bad "lints a submodule with its own ruleset"

FAKE_PHPCS=1 lint "$L/web/modules/custom/mine/src/B.php"
[[ "$rc" -eq 2 ]] && ok "sends phpcs violations back to Claude" || bad "sends phpcs violations back to Claude (exit $rc)"

FAKE_PHPCBF=1 lint "$L/web/modules/custom/mine/src/B.php"
[[ "$rc" -eq 0 ]] && jq -e '.hookSpecificOutput.additionalContext | test("Re-read")' <<< "$out" >/dev/null \
  && ok "an auto-fix that leaves phpcs clean is a note, not an error" \
  || bad "an auto-fix that leaves phpcs clean is a note, not an error (exit $rc)"

echo 'x;' > "$L/web/modules/custom/mine/b.js"
lint "$L/web/modules/custom/mine/b.js"
[[ "$rc" -eq 0 ]] && grep -qF "Skipping eslint: no ESLint config" "$L/err" \
  && ok "skips ESLint where it has no config" || bad "skips ESLint where it has no config (exit $rc)"

NOLIB="$TMP/nolib"
mkdir -p "$NOLIB"
cp "$HOOKS/post-generation-lint.sh" "$HOOKS/post-session-phpstan.sh" "$NOLIB/"
lint "$L/web/modules/custom/mine/src/B.php" "$NOLIB"
[[ "$rc" -eq 2 ]] && grep -qF "is missing" "$L/err" \
  && ok "lint says so when lib/ is missing" || bad "lint says so when lib/ is missing (exit $rc)"

echo "── post-session-phpstan: reports back once ─────"
S="$TMP/stan"
mkdir -p "$S/web/core" "$S/web/modules/custom/mine/src" "$S/vendor/bin"
echo '<?php' > "$S/web/modules/custom/mine/src/C.php"
echo 'parameters: {}' > "$S/phpstan.neon"
git_q "$S" init
git_q "$S" add -A
git_q "$S" commit -m init
echo '<?php // changed' > "$S/web/modules/custom/mine/src/C.php"

fake_phpstan() {
  printf '#!/usr/bin/env bash\necho "%s"\nexit %s\n' "$1" "$2" > "$S/vendor/bin/phpstan"
  chmod +x "$S/vendor/bin/phpstan"
}

fake_phpstan "[OK] No errors" 0
expect_exit 0 "passes when PHPStan is clean"         post-session-phpstan.sh "$S" '{"stop_hook_active": false}'
fake_phpstan "Invalid configuration: Unexpected item 'parameters › drupal'." 1
expect_exit 2 "sends a broken config back to Claude"  post-session-phpstan.sh "$S" '{"stop_hook_active": false}'
out=$(echo '{"stop_hook_active": false}' | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-session-phpstan.sh" 2>&1 >/dev/null || true)
grep -qF "configuration is broken" <<< "$out" && ok "names it a config problem, not a code error" \
                                              || bad "names it a config problem, not a code error"
fake_phpstan "Line 3: Undefined variable" 1
expect_exit 2 "sends code errors back to Claude"      post-session-phpstan.sh "$S" '{"stop_hook_active": false}'
expect_exit 0 "only reports on the follow-up stop"    post-session-phpstan.sh "$S" '{"stop_hook_active": true}'

fake_phpstan '$*' 1
mkdir -p "$S/web/modules/custom/up/src"
echo '<?php' > "$S/web/modules/custom/up/src/D.php"
git_q "$S/web/modules/custom/up" init
git_q "$S/web/modules/custom/up" add -A
git_q "$S/web/modules/custom/up" commit -m init
printf '[submodule "up"]\n\tpath = web/modules/custom/up\n\turl = https://example.com/up.git\n' > "$S/.gitmodules"
echo '<?php // changed' > "$S/web/modules/custom/up/src/D.php"
out=$(echo '{"stop_hook_active": false}' | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-session-phpstan.sh" 2>&1 >/dev/null || true)
grep -qF "web/modules/custom/up/src/D.php" <<< "$out" && ok "analyses files changed inside a submodule" \
                                                      || bad "analyses files changed inside a submodule"

rc=0; echo '{"stop_hook_active": false}' | CLAUDE_PROJECT_DIR="$S" bash "$NOLIB/post-session-phpstan.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] && ok "PHPStan says so when lib/ is missing" || bad "PHPStan says so when lib/ is missing (exit $rc)"
rc=0; echo '{"stop_hook_active": true}' | CLAUDE_PROJECT_DIR="$S" bash "$NOLIB/post-session-phpstan.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && ok "…but only reports it on the follow-up stop" || bad "…but only reports it on the follow-up stop (exit $rc)"

echo ""
echo "hooks: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
