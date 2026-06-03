# Drupal Coding Rules — Template

> This file is the source of managed rules injected into your project's `CLAUDE.md`.
> Lines 1-3 are skipped by setup.sh. Content below the `---` is what gets inserted.

---

## Version-specific guidance

See `.claude/drupal-version-guide.md` for version-specific patterns; prefer it over generic Drupal advice.

See `.claude/reference/examples/` for the canonical-patterns reference codebase (downloaded by setup, never installed by Drupal, gitignored) — use it as the source of truth for idiomatic, working examples before improvising.

## Managed `.gitignore` block

This workflow maintains an append-only block in your project `.gitignore`, delimited by the markers:

```
# >>> drupal-agentic-workflow >>>
…
# <<< drupal-agentic-workflow <<<
```

Everything between these markers is managed by `setup.sh` and refreshed on re-run. Do not edit, reorder, or "fix" these lines by hand — your changes will be overwritten. Add your own ignores outside the block.

## Critical Code Rules (Always Follow)

### Dependency Injection
- Constructor injection with interfaces (`EntityTypeManagerInterface`, not `EntityTypeManager`)
- Never `\Drupal::` in service classes — inject via constructor
- `AutowireTrait` for plugins when all services are standard container services
- Fall back to explicit `create()` only when runtime logic decides dependencies

### Plugins
- `final class` unless extension is explicitly intended
- Fully typed constructor params: `string $plugin_id`, `array $plugin_definition`

### Hooks
- Group related hooks by domain (`FormHooks`, `EntityHooks`)
- Inject services via constructor, never `\Drupal::` in hook classes

### Documentation
- No redundant docblocks — if the type says it, don't repeat it
- Document array structures (`@param array{key: type}`), side effects, and `@throws`
- `{@inheritdoc}` for overridden methods

### phpcs compliance — get it right on the first pass
`phpcbf` auto-fixes whitespace, indentation, and array syntax, but it has **no fixer** for the rules below — they survive auto-fix and surface as phpcs errors. Produce them correctly when generating code:
- **File doc comment**: every `.module`/`.inc`/`.install`/`.profile` file opens with a `@file` block; class files do not (one class per file).
- **Function/method docblocks**: a one-line summary ending in `.`, then `@param`/`@return`/`@throws` as needed — or `{@inheritdoc}` when overriding. Missing docblocks (`Drupal.Commenting.FunctionComment.Missing`) are the #1 survivor.
- **Comment line length ≤ 80 chars** (`Drupal.Files.LineLength`) — code lines are exempt, comments are not. Wrap long comments.
- **No unused `use` statements** and alphabetical `use` ordering.
- **Inline comments** are full sentences starting with a capital and ending in `.`, `!`, or `?`.
- **`@var` on every class property**; `@code`/`@endcode` for code samples in docblocks.
- **`t()` strings are literal** — no concatenation or variables inside `t()`; use `@placeholder`/`%placeholder` args.

### Testing
- Tests are expected for production code — use `/generate-tests` to scaffold them
- Unit tests for services with pure logic, Kernel tests for entity/DB interactions, Functional tests for user workflows

### Caching
- All render arrays must include `#cache` metadata (tags, contexts, max-age)
- Use `Cache::mergeTags()` / `Cache::mergeContexts()` to combine
- Entity cache tags via `$entity->getCacheTags()`

### Security
- `->accessCheck(TRUE)` on all entity queries (or `FALSE` with justification)
- Sanitize user input: `$this->t()`, `Xss::filter()`, `Html::escape()`
- In JS: `Drupal.checkPlain()` for any user-controlled data inserted into DOM

## Common Mistakes to Avoid

1. Missing `accessCheck()` on entity queries
2. Using `\Drupal::` in service classes — inject via constructor
3. Missing `#cache` on render arrays
4. Missing config schema for custom config
5. Business logic in controllers/hooks instead of services

## Skills Reference

Use slash commands for detailed guidance instead of repeating knowledge here:

### Backend
| Need | Skill |
|------|-------|
| Drupal development patterns, DI, testing | `/drupal-expert` |
| Custom content/config entity types | `/entity` |
| Generate modules, services, plugins, forms | `/scaffold` |
| Troubleshoot hooks, services, cache, routes | `/debug` |
| Code smells, god classes, anti-patterns | `/refactor` |
| Safe contrib module updates | `/update-module` |
| Drush CLI commands, SQL, deprecated commands | `/drush` |
| Migration management | `/migrate` |

### Frontend
| Need | Skill |
|------|-------|
| Twig, SDC, theming, CSS/JS | `/drupal-frontend-expert` |
| WCAG 2.2 compliance, ARIA, a11y testing | `/accessibility` |
| REST, JSON:API, GraphQL development | `/api` |

### AI & Agentic
| Need | Skill |
|------|-------|
| Drupal AI module, providers, FunctionCall plugins | `/drupal-ai` |
| AI Search, vector DB, embeddings, RAG | `/drupal-ai-search` |
| Custom Tool plugins, TypedDataAdapters | `/drupal-tool-api` |
| FlowDrop workflows, orchestrators, state graph | `/flowdrop` |
| FlowDrop visual agent editor | `/flowdrop-ui-agents` |

### Site Building & Config
| Need | Skill |
|------|-------|
| Views, content types, Layout Builder | `/drupal-site-builder-expert` |
| Config export/import, Config Split, Recipes | `/config-management` |
| Recipes with default content and translations | `/create-drupal-recipe` |
| Caching, queries, BigPipe, profiling | `/performance` |
| XSS, SQL injection, access control, CSRF | `/drupal-security` |

### Workflow
| Need | Skill |
|------|-------|
| Architectural code review | `/code-review` |
| Generate PHPUnit tests | `/generate-tests` |
| Estimate ticket complexity | `/estimate` |
| Plan a feature, break into tasks | `/create-plan` |
| DDEV environment management | `/ddev` |
| Local Solr setup for DDEV | `/solr-setup` |
| Workflow setup diagnostics | `/doctor` |

## Project knowledge files

Before generating code, **read the relevant files in `.claude/`** — they capture project-specific context that overrides generic Drupal conventions:

| File | When to read it |
|------|-----------------|
| `.claude/drupal-version-guide.md` | Before writing any PHP — version-specific patterns (PHP version, hook attribute style, Symfony/CKEditor versions) for the Drupal core in use. |
| `.claude/conventions.md` | Before writing PHP/JS/CSS — adoption stats for hook style, DI, `match`/`switch`, etc. Match what the codebase actually does, not the textbook. |
| `.claude/project-map.md` | Before touching the data model, routes, or services — structural overview of content types, fields, roles, routes per module, and services per module. |
| `.claude/glossary.md` | Before naming things — domain terms (German/English) used in UI, code, and commits. |
| `.claude/external-systems.md` | Before touching integrations — where API URLs, credentials, and IDs live (never invent endpoints). |
| `.claude/test-fixtures.md` | Before verifying behavior locally — demo users, payment sandboxes, seed content. |
| `.claude/decisions/*.md` | Before proposing architectural alternatives — append-only ADRs of decisions already made. |
| `.claude/stack.json` | Detected stack snapshot (PHP/Drupal/frontend versions, integrations). Source of truth for tooling assumptions. |
| `.claude/skills-recommended.md` | Capability → skill mapping for this project. Refer to it when picking which skill to invoke. |
| `.claude/gaps.md` | Capabilities without an installed skill + drift warnings — useful when planning new tooling. |
| `.claude/reference/examples/` | Canonical Drupal patterns checkout — read before improvising. Managed by setup, gitignored, never installed by Drupal. |

These files are scaffolded by `drupal-agentic-workflow` setup. Conventions/stack/gaps/version-guide are auto-generated and refreshed on re-run; glossary/external-systems/test-fixtures/decisions are filled in by the team and preserved across re-runs.
