# Drupal Agentic Workflow

Checks that run, not context that goes stale. This installs into a Drupal
project:

- **Hooks** that Claude Code runs every time: a guard against destructive
  commands and committed secrets; phpcbf/phpcs, ESLint, Stylelint, Prettier
  and cspell on every edited file; and PHPStan when Claude finishes a turn.
  See `.claude/hooks/README.md`.
- **The checks drupal.org's CI runs, working out of the box:** Coder and
  PHPStan from Composer, and Drupal core's own ESLint, Stylelint, Prettier
  and cspell with core's configs (installed by `yarn install` in core).
- **A working `phpstan.neon`** that actually loads phpstan-drupal.
- **`site-api.sh`**, which reads the running site's real service IDs,
  entity bundles, fields, routes and permissions on demand.
- **A short AGENTS.md template**, plus a CLAUDE.md that imports it.

## Why it is this small

Agents read the code well, so a context file that restates the code (module
lists, versions, file layouts, convention statistics) mostly costs attention
on every task and goes stale with the next change. Anthropic's guidance is to
write down only what an agent can't find by reading the repo, keep the file
under 200 lines, and move rules that must never be broken into hooks:

- https://code.claude.com/docs/en/best-practices
- https://code.claude.com/docs/en/memory

Earlier versions generated `stack.json`, `conventions.md`,
`project-map.md`, glossary/ADR scaffolds and a 160-line managed AGENTS.md
block. They were removed after they drifted out of date on a real project and
pointed agents at wrong facts. The `scaffold`, `ddev` and `generate-tests`
skills went for the same reason: current models already write that code and
know those commands, and the templates had drifted from Drupal 11 (for
example `#[Hook]` classes no longer need a `services.yml` entry).

## Install

```bash
# As a Composer dev dependency (add the VCS repository first until it is on Packagist):
composer config repositories.daw vcs https://github.com/gxleano/drupal-agentic-workflow
composer require --dev gxleano/drupal-agentic-workflow:dev-main
vendor/bin/daw install

# Or from a clone:
~/drupal-agentic-workflow/bin/setup.sh /path/to/drupal/project
```

`install` checks for `drupal/coder`, `phpstan/phpstan`,
`mglaman/phpstan-drupal` and `phpstan/phpstan-deprecation-rules`, and offers
to require the missing ones (DDEV when the project has it, host Composer
otherwise). It offers to install Drupal core's JS dev tools (`yarn install`
in core, Yarn 4 through corepack; in DDEV when the project has it), links
`<docroot>/.prettierrc.json` to core's so Prettier agrees with drupal.org's
CI, and offers to add the missing phpstan-drupal `includes` to an existing
`phpstan.neon` that cannot load it. Every offer defaults to yes. The prompts read
from the terminal; without one (a script) the answer is no unless you pass
`--yes`.

Core's `node_modules` goes when Composer updates core: run `daw install`
again after a core update. The hooks say so when the tools are missing.

`daw update` re-copies the hooks and the site-api tool without prompts.
Neither command overwrites a file you changed (use `--force`), and neither
touches an existing AGENTS.md or CLAUDE.md. An existing
`.claude/settings.json` is merged: the workflow's hooks are added next to the
ones already there.

Options: `--dry-run`, `--force`, `--skip-tools`, `--yes` (accept every offer
without asking, for scripts and CI).

## After installing

1. **Fill in AGENTS.md.** Keep the four sections — Commands, what is project
   code and what is not, Gotchas, Conventions for new code — and run every
   command before you write it down.
2. **Check the hooks fire.** Edit a PHP file in a Claude Code session; the
   lint output should appear. A hook that exits with anything but 0 or 2 is
   ignored silently.
3. **Use the site index when it matters:** `.claude/tools/site-api.sh --print`.
   It is not generated at install time on purpose.

Upgrading a project set up by an older version: setup leaves your AGENTS.md
alone and warns if it still has the old `drupal-agentic-workflow:start` block.
Trim it by hand using `AGENTS-TEMPLATE.md`. The old `.claude/` files
(`conventions.md`, `project-map.md`, `stack.json`, …) are not removed
automatically.

## Tests

```bash
composer test   # or: bash tests/run.sh
```

Runs `bash -n` and shellcheck on every script, `tests/smoke.sh` (installs
into throwaway projects and checks the result) and `tests/hooks.sh` (feeds
each hook the JSON Claude Code sends and checks the exit code).
