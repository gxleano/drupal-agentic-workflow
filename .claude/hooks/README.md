# Claude Code Post-Generation Lint Hook

Automatically formats and lints files after Claude Code writes or edits them.

## How It Works

The hook is registered on the `PostToolUse` event (filtered to `Write|Edit` tools) in `.claude/settings.json`. Every time Claude modifies a file, the hook:

1. Reads the modified file path from the hook's JSON input (stdin)
2. Skips files outside the project scope (vendor, contrib, core, node_modules)
3. Detects the file type by extension
4. Runs **Prettier** formatting first (if available)
5. Runs the relevant **linters** on the formatted output
6. Exits with code `2` (blocking) if any tool fails — Claude sees the errors and can auto-correct

## File Type Detection

| Type | Extensions | Tools |
|------|-----------|-------|
| Backend (PHP/Drupal) | `.php` `.module` `.theme` `.install` `.inc` `.profile` `.test` | `phpcs`, security-perf-scan |
| JavaScript | `.js` `.jsx` `.ts` `.tsx` `.mjs` `.cjs` | `prettier`, `eslint` |
| Stylesheets | `.css` `.scss` `.sass` `.less` | `prettier`, `stylelint` |
| Twig templates | `.twig` `.html.twig` | `prettier` (with plugin) |
| Data files | `.yaml` `.yml` `.json` | `prettier` |

Only files in lintable paths are checked. These directories are always skipped:

- `vendor/`
- `node_modules/`
- `web/core/`
- `web/modules/contrib/`
- `web/themes/contrib/`
- `web/profiles/`

## Formatting (Prettier)

Prettier runs **before** linters on supported file types (JS/TS, CSS/SCSS, Twig, YAML, JSON). This ensures linters check already-formatted code, avoiding format-vs-lint conflicts.

- **Graceful degradation**: If Prettier is not installed, the step is skipped silently
- **Twig support**: Requires `prettier-plugin-twig-melody`. If the plugin is missing, Twig files skip Prettier but other file types still format
- **Configuration**: Uses `.prettierrc.json` at the project root
- **PHP is excluded**: phpcs/phpcbf handles PHP formatting

### Install Prettier

```bash
npm install --save-dev prettier
# Optional: Twig formatting
npm install --save-dev prettier-plugin-twig-melody
```

## Backend Tools

- **phpcs** — Drupal coding standards (Drupal + DrupalPractice), runs inside DDEV via `ddev exec`
- **security-perf-scan** — Fast local grep for dangerous patterns (`eval()`, `shell_exec()`, `\Drupal::` in src/, missing `accessCheck()`)

## Frontend Tools

Run on the host via `npx`:

- **prettier** — Code formatting (JS/TS, CSS/SCSS, Twig, YAML, JSON)
- **eslint** — JavaScript/TypeScript linting
- **stylelint** — CSS/SCSS linting

## Execution Order

```
File modified by Claude
  └─ Is lintable path? (not vendor/contrib/core)
      └─ Is Prettier target? → Run Prettier --write
      └─ Is PHP? → Run phpcs + security-perf-scan
      └─ Is JS/TS? → Run eslint
      └─ Is CSS/SCSS? → Run stylelint
      └─ Log summary, exit 2 if errors
```

## Requirements

- `jq` (to parse hook input)
- `ddev` (for PHP linting)
- `npx` (for frontend tools, optional — skipped if unavailable)
- `prettier` (optional — skipped if not installed)
- `prettier-plugin-twig-melody` (optional — Twig formatting only)
