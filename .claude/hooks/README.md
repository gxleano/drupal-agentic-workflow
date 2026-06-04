# Claude Code Hooks

Hooks that run automatically during Claude Code sessions to enforce code quality and prevent destructive operations.

## Registered Hooks

| Hook | Event | Matcher | File | Purpose |
|------|-------|---------|------|---------|
| **Pre-Bash Guard** | PreToolUse | Bash | `pre-bash-guard.sh` | Blocks destructive commands |
| **Post-Generation Lint** | PostToolUse | Write\|Edit | `post-generation-lint.sh` | Auto-fix + lint + security scan |
| **Post-Session PHPStan** | Stop | — | `post-session-phpstan.sh` | PHPStan on changed files after each turn |
| **Prompt Context** | UserPromptSubmit | (opt-in) | `prompt-context.sh` | Git status injection |

## Pre-Bash Guard (`pre-bash-guard.sh`)

**Event**: PreToolUse (Bash)
**Timeout**: 5 seconds
**Exit code 2**: Block the command

Prevents Claude from running destructive operations that are hard to reverse.

### Blocked Commands

| Command | Reason |
|---------|--------|
| `git reset --hard` | Destroys uncommitted changes |
| `git checkout -- .` / `git checkout .` | Discards all working tree changes |
| `git clean -f` | Permanently deletes untracked files |
| `git push --force` / `git push -f` | Rewrites remote history |
| `git branch -D` | Force-deletes a branch without merge check |
| `rm -rf /` / `rm -rf .` / `rm -rf ~` / `rm -rf $HOME` | Catastrophic file deletion |
| `ddev delete` | Destroys the DDEV project and its database |
| `DROP TABLE` / `DROP DATABASE` | Permanently destroys database objects |
| `drush sql:drop` / `sql-drop` | Drops every table in the database |
| `drush sql:query`/`sql:cli` with `DROP`/`TRUNCATE`/`DELETE` | Destroys data |
| `drush entity:delete` | Bulk-deletes content entities |
| `drush field:delete` | Removes a field and all its data |
| `drush state:delete` | Removes persisted system state |
| `drush user:cancel` | Cancels/deletes user accounts and their content |

Drush patterns match both the `cmd:sub` and legacy `cmd-sub` separators.

> **This is a guardrail, not a sandbox.** It pattern-matches command strings, so a determined or obfuscated command (env-prefixed, `eval`, `;`-chained, aliased) can still slip through. It catches the common accidents — it is not a security boundary.

### How It Works

1. Reads the Bash command from stdin JSON (`tool_input.command`)
2. Pattern-matches against known destructive commands
3. Exits 0 (allow) or 2 (block with feedback message)

## Post-Generation Lint (`post-generation-lint.sh`)

**Event**: PostToolUse (Write|Edit)
**Timeout**: 120 seconds
**Exit code 2**: Report errors to Claude for auto-correction

Automatically formats and lints files after Claude Code writes or edits them.

### Execution Pipeline

```
File modified by Claude
  └─ Is lintable path? (not vendor/contrib/core)
      └─ Is PHP?
      │   ├─ phpcbf auto-fix (best-effort, non-blocking)
      │   ├─ phpcs (blocking if violations)
      │   └─ security-perf-scan (blocking if issues)
      └─ Is Prettier target? → Run Prettier --write
      └─ Is JS/TS? → Run eslint
      └─ Is CSS/SCSS? → Run stylelint
      └─ Log summary, exit 2 if errors
```

### File Type Detection

| Type | Extensions | Tools |
|------|-----------|-------|
| Backend (PHP/Drupal) | `.php` `.module` `.theme` `.install` `.inc` `.profile` `.test` | `phpcbf`, `phpcs`, security-perf-scan |
| JavaScript | `.js` `.jsx` `.ts` `.tsx` `.mjs` `.cjs` | `prettier`, `eslint` |
| Stylesheets | `.css` `.scss` `.sass` `.less` | `prettier`, `stylelint` |
| Twig templates | `.twig` `.html.twig` | `prettier` (with plugin) |
| Data files | `.yaml` `.yml` `.json` | `prettier` |

### Skipped Directories

- `vendor/`
- `node_modules/`
- `web/core/`
- `web/modules/contrib/`
- `web/themes/contrib/`
- `web/profiles/`

### Backend Tools

- **phpcbf** — Auto-fixes coding standard violations (runs before phpcs, best-effort). Many sniffs (missing docblocks, `@file`, comment line length, `t()` literals) have **no fixer** and survive to phpcs.
- **phpcs** — Runs with `-s` so sniff codes are shown, making remaining violations actionable. When phpcbf rewrote the file, the feedback includes a note that the on-disk file is now stale and must be re-read before further edits.

#### Standard & runner resolution

- **Standard**: prefers the project's own ruleset (`phpcs.xml`, then `phpcs.xml.dist`) so the hook agrees with CI exactly; falls back to the bundled `Drupal,DrupalPractice` (with the default extension list) when no ruleset is present.
- **Runner**: resolved by the shared `lib/php-tools.sh` in this order — `ddev exec` (when `.ddev/config.yaml` exists **and** DDEV is running) → the repo's own `vendor/bin/phpcs`/`phpcbf` → a `phpcs`/`phpcbf` on `$PATH` → a global Composer install (`~/.composer` / `~/.config/composer`). The `$PATH` and global fallbacks let the hook lint a **standalone contrib module/theme repo that has no Drupal installation or DDEV**. If none is found, the PHP CS step is skipped with a one-line install hint instead of failing silently.
- **Broken Coder install** (missing standard / binary) is detected in tool output and reported as a setup problem with the `composer require --dev drupal/coder` + `--config-set installed_paths` fix, rather than masquerading as a code error.
- **Non-runnable binary** (exit 127 — e.g. a global `phpcs` shim that expects a project-local install) is treated as "no tool available": the CS step is skipped non-blockingly with an install hint, never reported as a code error.
- **security-perf-scan** — Fast local grep for dangerous patterns:
  - Security: `eval()`, `shell_exec()`, `passthru()`, `proc_open()`, `popen()`, `$_GET/$_POST/$_REQUEST`, `unserialize()`, `extract()`
  - Performance: `\Drupal::` in `src/`, missing `accessCheck()` on entity queries

### Frontend Tools

Run on the host via `npx`:

- **prettier** — Code formatting (JS/TS, CSS/SCSS, Twig, YAML, JSON)
- **eslint** — JavaScript/TypeScript linting
- **stylelint** — CSS/SCSS linting

### Formatting (Prettier)

Prettier runs **before** linters on supported file types. This ensures linters check already-formatted code.

- **Graceful degradation**: Skipped silently if not installed
- **Twig support**: Requires `prettier-plugin-twig-melody`
- **PHP is excluded**: phpcbf/phpcs handles PHP formatting
- **Drupal-managed YAML is excluded**: files under `config/` and module/theme definition YAML (`*.info.yml`, `*.routing.yml`, `*.services.yml`, `*.libraries.yml`, `*.permissions.yml`, `*.links.*.yml`, `*.breakpoints.yml`, `*.schema.yml`, `*.settings.yml`) are left untouched. Drupal's exporter uses its own YAML style, so prettier would cause `drush cex` churn and can alter semantically significant quoting. Generic `.yml`/`.yaml`/`.json` are still formatted.

Install:
```bash
npm install --save-dev prettier
npm install --save-dev prettier-plugin-twig-melody  # optional
```

## Post-Session PHPStan (`post-session-phpstan.sh`)

**Event**: Stop
**Timeout**: 120 seconds
**Exit code**: Always 0 (informational — output shown to user, not fed back to Claude)

Runs PHPStan once after Claude finishes each turn, analysing the PHP files changed since the last commit. This avoids per-file overhead and runs PHPStan when its result cache is already warm from the session's edits.

The hook adapts to two contexts (detected by the shared `lib/php-tools.sh`):

- **Drupal site** (a docroot with core checked out): scans changed files under `web/modules/custom/` — the original behaviour.
- **Standalone repo** (a contrib module/theme/profile with an `*.info.yml` at the root, or a `drupal-module`/`-theme`/`-profile` composer.json, and **no Drupal installation**): scans changed PHP anywhere in the repo, still excluding vendored/contrib/core paths.

The phpstan binary is resolved with the same order as phpcs: `ddev exec` → `vendor/bin/phpstan` → `$PATH` → global Composer — so it runs locally when there's no container.

### Execution Flow

```
Claude finishes turn
  └─ phpstan resolvable? (ddev / vendor-bin / PATH / global — skip if not)
      └─ context = site | module
          └─ config: phpstan.neon(.dist) → use it
                     else (local run) → synthesize a config (level 1):
                         • phpstan-drupal found → include its extension.neon
                         • not found            → barebones phpstan
                     else (ddev, no config)  → skip
              └─ Any changed PHP? (site: web/modules/custom/ only)
                  └─ phpstan analyse --no-progress <changed files>
                      ├─ PASSED → brief confirmation
                      └─ FAILED → issue list + tip to ask Claude to fix
```

### Skipped When

- No phpstan binary is resolvable in any of: DDEV, `vendor/bin`, `$PATH`, global Composer
- Running via DDEV with no project `phpstan.neon`/`.dist` (host paths can't be synthesized into the container)
- No changed PHP files in scope for the detected context

### Output

Results appear as a notification after Claude's response, including the detected context, runner, and which config was used. If issues are found, ask Claude to fix them in the next turn.

### Requirements

- `phpstan/phpstan` (and, for Drupal-aware analysis, `mglaman/phpstan-drupal`) reachable via DDEV, `vendor/bin`, `$PATH`, or a global Composer install
- For containerised runs: `phpstan.neon` in the project root (generated by `setup.sh`) and DDEV running (`ddev start`)
- For standalone module repos: a local phpstan install; a `phpstan.neon`/`.dist` is preferred but not required (a level-1 config is synthesized when absent)

## Prompt Context (`prompt-context.sh`) — Opt-in

**Event**: UserPromptSubmit
**Timeout**: 5 seconds

Injects a 1-2 line git status summary at every prompt. Example output:
```
[Git: feature/my-branch — 3 modified, 1 untracked]
```

### Enabling

This hook is **opt-in**. Add to `.claude/settings.local.json` (NOT `settings.json`):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prompt-context.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Requirements

- `jq` — required by all hooks for JSON parsing
- A PHP linting toolchain reachable via **one of**: `ddev`, the repo's `vendor/bin`, `$PATH`, or a global Composer install. DDEV is no longer required — a standalone contrib module repo with a local `phpcs`/`phpstan` works too.
- `npx` — for frontend tools (optional, skipped if unavailable)
- `prettier` — optional, for formatting (skipped if not installed)
- `git` — required by prompt-context.sh

## Adding Custom Hook Patterns

### Adding Security Scan Patterns

Edit the security scan section in `post-generation-lint.sh`:

```bash
scan_pattern "SECURITY" 'your_pattern_here' \
  "Description of the issue and how to fix it."
```

### Adding Pre-Bash Guard Patterns

Edit `pre-bash-guard.sh` to add new blocked commands:

```bash
if echo "$COMMAND" | grep -qE 'your_pattern'; then
  block "Description of why this is blocked"
fi
```
