# AGENTS.md

<!--
Keep this file under ~150 lines. It loads into every agent session, so each
line costs attention on every task. Before adding a line, ask:
  1. Could the agent find this by reading the repo?
  2. Would it actually go and look?
If both are yes, leave it out. Versions, module lists and file layouts fail
that test (they are in composer.lock, *.info.yml and the tree) and go stale.

Run every command before you write it down. Delete these comments when done.
-->

TODO: one or two sentences — what this site is and who uses it.

## Commands

Run site commands through DDEV (`ddev drush …`, `ddev composer …`), never
host PHP.

- Coding standards: `ddev exec vendor/bin/phpcs --standard=Drupal,DrupalPractice --extensions=php,module,inc,install <path>`
- Static analysis: `ddev exec vendor/bin/phpstan analyse <path>`
- Tests: TODO — the exact command, and how to run a single test file.
- Build / deploy: TODO — only if they are not obvious from the repo.
- Real service IDs, bundles, fields, routes and permissions of the running
  site: `.claude/tools/site-api.sh --print` (run it; don't trust an old copy).

## What is project code and what is not

<!-- Which directories are yours, which are contrib, patches, submodules or
generated. Where edits must NOT go, and why. -->

## Gotchas

<!-- Places where the code misleads: a pattern that is everywhere but must not
be copied, a directory that looks unused but is live, two configs that look
alike but are not. Anything you have had to correct an agent on twice. -->

## Conventions for new code

<!-- Only decisions an agent cannot infer from the surrounding code, e.g. when
older code uses a pattern new code must not copy. -->
