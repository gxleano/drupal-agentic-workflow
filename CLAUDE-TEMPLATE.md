# Drupal 11 Coding Rules — Template

> This file is the source of managed rules injected into your project's `CLAUDE.md`.
> Lines 1-3 are skipped by setup.sh. Content below the `---` is what gets inserted.

---

## Critical Code Rules (Always Follow)

### PHP / Drupal 11
- `declare(strict_types=1)` on all new PHP files
- `protected readonly` constructor property promotion for injected services
- PHP attributes (`#[Block]`, `#[Hook]`) instead of docblock annotations
- `match` instead of `switch` for simple conditionals
- `static` instead of `self` in `create()` methods and factories
- Fully type all parameters, properties, and return types
- 2-space indentation, `\Exception` not `use Exception`, `@todo` not `TODO:`

### Dependency Injection
- Constructor injection with interfaces (`EntityTypeManagerInterface`, not `EntityTypeManager`)
- Never `\Drupal::` in service classes — inject via constructor
- `AutowireTrait` for plugins when all services are standard container services
- Fall back to explicit `create()` only when runtime logic decides dependencies

### Plugins
- `#[Block(...)]` attribute, not `@Block(...)` annotation
- `final class` unless extension is explicitly intended
- Fully typed constructor params: `string $plugin_id`, `array $plugin_definition`

### Hooks
- `#[Hook]` attribute classes in `src/Hook/` for all new hooks
- Only `hook_theme()`, `hook_preprocess_*()`, `hook_install()`, `hook_update_N()` stay in `.module`
- Group related hooks by domain (`FormHooks`, `EntityHooks`)
- Inject services via constructor, never `\Drupal::` in hook classes

### Documentation
- No redundant docblocks — if the type says it, don't repeat it
- Document array structures (`@param array{key: type}`), side effects, and `@throws`
- `{@inheritdoc}` for overridden methods

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
4. `@Block` annotation instead of `#[Block]` attribute
5. Hooks in `.module` that should be in `src/Hook/`
6. Missing config schema for custom config
7. `switch` instead of `match` for simple conditionals
8. `self` instead of `static` in `create()` methods
9. Missing `declare(strict_types=1)` on new PHP files
10. Business logic in controllers/hooks instead of services

## Skills Reference

Use slash commands for detailed guidance instead of repeating knowledge here:

| Need | Skill |
|------|-------|
| Drupal development patterns, DI, testing | `/drupal-expert` |
| Twig, SDC, theming, CSS/JS, a11y | `/drupal-frontend-expert` |
| XSS, SQL injection, access control, CSRF | `/drupal-security` |
| Views, content types, Layout Builder | `/drupal-site-builder-expert` |
| Config export/import, Config Split, Recipes | `/config-management` |
| Caching, queries, BigPipe, profiling | `/performance` |
| Generate modules, services, plugins, forms | `/scaffold` |
| Troubleshoot hooks, services, cache, routes | `/debug` |
| Code smells, god classes, anti-patterns | `/refactor` |
| Safe contrib module updates | `/update-module` |
| Drush CLI commands, SQL, deprecated commands | `/drush` |
| Migration management | `/migrate` |
