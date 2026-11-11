# Claude Code Hooks

Hooks are the deterministic part of the workflow: Claude Code runs them every
time, whatever the model decides. Instructions in AGENTS.md are guidelines the
model may skip; rules that must never be broken belong here.

| Hook | Event | Matcher | Script | Effect |
|------|-------|---------|--------|--------|
| Pre-Bash Guard | PreToolUse | Bash | `pre-bash-guard.sh` | Blocks destructive commands and secrets reaching git |
| Post-Generation Lint | PostToolUse | Write\|Edit | `post-generation-lint.sh` | Auto-fixes and lints the edited file |
| Post-Session PHPStan | Stop | — | `post-session-phpstan.sh` | Analyses changed PHP when Claude finishes a turn |

Exit code 2 sends the hook's stderr back to Claude. Any other non-zero exit is
a non-blocking error that Claude Code ignores, so the two PHP hooks turn any
unexpected exit (a missing `lib/`, a failing command under `set -e`) into
exit 2 with a note instead of failing silently. `tests/hooks.sh` in the
workflow repo covers each one.

`lib/php-tools.sh` is shared by the two PHP hooks and must be installed next
to them. It resolves phpcs, phpcbf and phpstan in this order: DDEV
(`ddev exec`, when `ddev describe` reports the project running) → `vendor/bin` → `$PATH` → the
global Composer bin directory.

## Pre-Bash Guard

Blocks, with exit 2:

- `git reset --hard`, `git checkout -- .`, `git clean -f`, `git push --force`,
  `git branch -D`
- `rm -rf` on `/`, `.`, `..` or the home directory
- `ddev delete`
- `drush sql:drop`, `sql:query`/`sql:cli` with DROP/TRUNCATE/DELETE,
  `entity:delete`, `field:delete`, `state:delete`, `user:cancel`
- `DROP TABLE` / `DROP DATABASE`
- **Secrets reaching git:** `git add` of `.env`, `.env.local`,
  `.env.*.local` or `settings.local.php` (also with `-f`); `git add -A`/`.`
  when such a file is untracked and not ignored; `git commit` (and
  `commit -a`) when one is staged or modified. `.env.example` is allowed.

It pattern-matches command strings: a guardrail against accidents, not a
sandbox.

## Post-Generation Lint

Runs on the file Claude just wrote or edited:

- **PHP** (`.php .module .theme .install .inc .profile .test`): phpcbf, then
  phpcs with `-s`. Uses the project's `phpcs.xml(.dist)` if present, else
  `Drupal,DrupalPractice`. When phpcbf rewrote the file and phpcs is clean,
  Claude gets a note (as context, exit 0) to re-read the file before editing
  it again.
- **JS/TS**: Prettier, then ESLint. **CSS/SCSS**: Prettier, then Stylelint.
  ESLint and Stylelint run only where a config file sits between the file and
  the project root, and a linter that cannot load its config (ESLint 9+ with
  core's `.eslintrc.json`) is reported, not sent back as a code error. Tools
  run through `npx --no-install`, so nothing is downloaded.
- **Twig/YAML/JSON**: Prettier. Drupal config and definition YAML is never
  reformatted (`drush cex` would undo it).

Skipped: `vendor/`, `node_modules/`, core, contrib and profiles.

**Git submodules** hold upstream projects with their own standards: their
files are checked with phpcs (and ESLint/Stylelint) against the submodule's
own `phpcs.xml(.dist)`, else `Drupal,DrupalPractice`, but never auto-fixed by
phpcbf or Prettier.

## Post-Session PHPStan

Runs `phpstan analyse` on PHP files changed in the working tree (under
`web/modules/custom/` on a site; anywhere in a standalone module repo),
including files changed inside git submodules. Uses
the project's `phpstan.neon(.dist)`; a standalone repo without one gets a
temporary level-1 config.

- Clean → exit 0.
- Errors, or PHPStan cannot run at all (for example a broken config) → exit 2
  once, so Claude sees it. A broken config is labelled as such, not as a code
  error.
- On the follow-up stop (`stop_hook_active`) it only reports, so files with
  pre-existing errors cannot trap Claude in a loop.
