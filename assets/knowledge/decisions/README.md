# Architecture Decision Records

One file per decision. Numbered sequentially. **Append-only** — when a decision is superseded, create a new ADR and update the old one's `Status` to `superseded by NNNN`.

Copy `0001-template.md` to `NNNN-short-slug.md` for new decisions (e.g. `0002-use-config-split.md`).

## Why ADRs?

The coding agent (and future you) won't re-litigate decisions if the *why* is captured. A 5-minute note here saves an hour of debate later, and the agent will stop suggesting alternatives you've already ruled out.

## What to record

- **Architectural choices**: framework version, multisite vs single, headless vs traditional
- **Library/module selection** when alternatives existed
- **Workflow choices**: branching model, deploy target, env split strategy
- **Schema/data model decisions** with non-obvious tradeoffs
- **Anti-patterns explicitly rejected**

## What NOT to record

- Routine bug fixes (use git log)
- Trivial style choices (use `.editorconfig`, `phpcs.xml`)
- Anything captured by `.claude/conventions.md` automatically
