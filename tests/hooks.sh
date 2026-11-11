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

echo "── post-generation-lint: Drupal core's JS tools ─"
C="$TMP/corejs"
CB="$C/web/core/node_modules/.bin"
mkdir -p "$CB" "$C/web/modules/custom/my_mod/js" "$C/web/modules/custom/my_mod/css" "$C/web/modules/custom/own/js"
echo '{}' > "$C/web/core/package.json"
for f in .eslintrc.passing.json .stylelintrc.json .prettierrc.json .cspell.json; do echo '{}' > "$C/web/core/$f"; done
echo 'name: My mod' > "$C/web/modules/custom/my_mod/my_mod.info.yml"
echo 'name: Own' > "$C/web/modules/custom/own/own.info.yml"
echo '{"rules": {}}' > "$C/web/modules/custom/own/.eslintrc.json"
echo 'flowdrop' > "$C/web/modules/custom/my_mod/.cspell-project-words.txt"
# Fake core tools: log their arguments; cspell also keeps its config.
for t in eslint stylelint prettier; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls"\nexit "${FAKE_%s:-0}"\n' \
    "$t" "$C" "$(echo "$t" | tr '[:lower:]' '[:upper:]')" > "$CB/$t"
done
printf '#!/usr/bin/env bash\necho "cspell $*" >> "%s/calls"\ncp "$2" "%s/cspell.json"\nexit "${FAKE_CSPELL:-0}"\n' "$C" "$C" > "$CB/cspell"
chmod +x "$CB"/*
echo 'x;' > "$C/web/modules/custom/my_mod/js/a.js"
echo 'a {}' > "$C/web/modules/custom/my_mod/css/a.css"
echo 'x;' > "$C/web/modules/custom/own/js/b.js"
corelint() {
  : > "$C/calls"
  out=$(file_json "$1" | CLAUDE_PROJECT_DIR="$C" bash "$HOOKS/post-generation-lint.sh" 2>"$C/err") && rc=0 || rc=$?
}

if command -v node >/dev/null; then
  corelint "$C/web/modules/custom/my_mod/js/a.js"
  grep -q -- '^eslint .*--no-eslintrc -c web/core/.eslintrc.passing.json' "$C/calls" \
    && grep -q -- '--resolve-plugins-relative-to web/core' "$C/calls" \
    && ok "lints JS with core's ESLint and CI's passing config" || bad "lints JS with core's ESLint and CI's passing config"
  grep -q -- '^prettier --write --config web/core/.prettierrc.json' "$C/calls" \
    && ok "formats with core's Prettier config" || bad "formats with core's Prettier config"
  jq -e '(.words | index("my") and index("mod")) and (.dictionaries | index("project-words")) and (.flagWords | length > 0)' \
    "$C/cspell.json" >/dev/null && ok "spell-checks like CI: module name parts, project words, flagged words" \
    || bad "spell-checks like CI: module name parts, project words, flagged words"

  corelint "$C/web/modules/custom/own/js/b.js"
  grep -q -- '--no-eslintrc' "$C/calls" && bad "a module's own ESLint config wins" || ok "a module's own ESLint config wins"

  corelint "$C/web/modules/custom/my_mod/css/a.css"
  grep -q -- '^stylelint --config-basedir web/core --config web/core/.stylelintrc.json' "$C/calls" \
    && ok "lints CSS with core's Stylelint config" || bad "lints CSS with core's Stylelint config"

  FAKE_CSPELL=1 corelint "$C/web/modules/custom/my_mod/js/a.js"
  [[ "$rc" -eq 2 ]] && grep -qF ".cspell-project-words.txt" "$C/err" \
    && ok "sends spelling errors back with where to add real words" \
    || bad "sends spelling errors back with where to add real words (exit $rc)"
else
  echo "  (node not found: skipping the core JS tool checks)"
fi

mv "$C/web/core/node_modules" "$C/web/core/node_modules.off"
corelint "$C/web/modules/custom/my_mod/js/a.js"
[[ "$rc" -eq 0 ]] && grep -qF "daw install" "$C/err" \
  && ok "says how to install core's JS tools when they are missing" \
  || bad "says how to install core's JS tools when they are missing (exit $rc)"

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
echo '<?php' > "$S/web/modules/custom/mine/src/New.php"
out=$(echo '{"stop_hook_active": false}' | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-session-phpstan.sh" 2>&1 >/dev/null || true)
grep -qF "web/modules/custom/mine/src/New.php" <<< "$out" && ok "analyses new, untracked files" || bad "analyses new, untracked files"
rm "$S/web/modules/custom/mine/src/New.php"

# Session scope: only files the lint hook saw in this session are analysed.
SID="test-session-$$"
EDITS="${TMPDIR:-/tmp}/claude-daw-edits-$SID"
rm -f "$EDITS"
echo '<?php // changed again' > "$S/web/modules/custom/mine/src/C.php"
rc=0; jq -cn --arg s "$SID" '{session_id: $s, stop_hook_active: false}' \
  | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-session-phpstan.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && ok "skips files Claude did not edit in the session" || bad "skips files Claude did not edit in the session (exit $rc)"
jq -cn --arg f "$S/web/modules/custom/mine/src/C.php" --arg s "$SID" '{session_id: $s, tool_input: {file_path: $f}}' \
  | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-generation-lint.sh" >/dev/null 2>&1 || true
out=$(jq -cn --arg s "$SID" '{session_id: $s, stop_hook_active: false}' \
  | CLAUDE_PROJECT_DIR="$S" bash "$HOOKS/post-session-phpstan.sh" 2>&1 >/dev/null || true)
grep -qF "web/modules/custom/mine/src/C.php" <<< "$out" && ok "analyses a file Claude edited in the session" \
  || bad "analyses a file Claude edited in the session"
rm -f "$EDITS"

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
